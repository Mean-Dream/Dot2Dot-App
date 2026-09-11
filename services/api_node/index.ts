import 'dotenv/config';
import axios from 'axios';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { createClient } from '@supabase/supabase-js';

const app = express();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error('❌ Missing required environment variables: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
}

const PYTHON_WORKER_URL = process.env.PYTHON_WORKER_URL || 'http://localhost:8090';

// 10 uploads per user per 15 minutes — prevents a single user from
// saturating the Python worker queue with back-to-back AI jobs.
const uploadLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 10,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { error: 'Too many uploads. Please wait a few minutes and try again.' },
});

// 30 reprocesses per user per minute — generous enough for slider
// adjustments but blocks runaway loops.
const reprocessLimiter = rateLimit({
    windowMs: 60 * 1000,
    limit: 30,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { error: 'Too many reprocess requests. Slow down a little.' },
});

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

app.use(cors());
app.use(express.json({ limit: '50mb' }));

const MAX_FILE_BYTES = 15 * 1024 * 1024; // 15 MB

// Detect image type from magic bytes — never trust the client's claimed type.
function detectMimeType(buf: Buffer): string | null {
    if (buf.length < 12) return null;
    if (buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'image/jpeg';
    if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47) return 'image/png';
    if (buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46) return 'image/gif';
    if (buf[0] === 0x42 && buf[1] === 0x4D) return 'image/bmp';
    // WebP: RIFF????WEBP
    if (buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 &&
        buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50) return 'image/webp';
    return null;
}

app.post('/upload', uploadLimiter, async (req, res) => {
    console.log("📥 Received Request Body:", req.body); // 🔍 Check if userId/projectId are here

    const { image, name, sparsity, removeBg, userId, projectId, erased_points } = req.body;

    try {
        const buffer = Buffer.from(image, 'base64');

        if (buffer.length > MAX_FILE_BYTES) {
            return res.status(400).json({ error: 'File too large. Maximum size is 15 MB.' });
        }

        const mimeType = detectMimeType(buffer);
        if (!mimeType) {
            return res.status(400).json({ error: 'Invalid file type. Only JPEG, PNG, WebP, GIF, and BMP images are accepted.' });
        }

        const fileName = `${Date.now()}-${name}`;

        console.log("☁️ Attempting Storage Upload...");
        const { error: storageError } = await supabase.storage
            .from('images')
            .upload(fileName, buffer, { contentType: mimeType });

        if (storageError) {
            console.error("❌ Storage Error:", storageError);
            throw storageError;
        }

        const projectPayload: any = { 
            image_path: fileName, 
            status: 'processing',
            sparsity: Number(sparsity) || 20,
            remove_bg: Boolean(removeBg),
            user_id: userId,
            // 🎯 ADD THIS: Save the erased points to the DB column
            erased_points: erased_points || [] 
        };

        if (projectId) projectPayload.id = projectId;

        console.log("💾 Attempting Database Upsert with Payload:", projectPayload);
        const { data: project, error: projectError } = await supabase
            .from('projects')
            .upsert(projectPayload)
            .select()
            .single();

        if (projectError) {
            console.error("❌ Database Error:", projectError); // 🎯 This is the likely killer
            throw projectError;
        }

        console.log("🟢 Database Success. ID:", project.id);

        // TRIGGER PYTHON (Using Axios for stability)
        axios.post(`${PYTHON_WORKER_URL}/process`, {
            projectId: project.id, 
            sparsity: Number(sparsity),
            removeBg: Boolean(removeBg),
            erased_points: erased_points || [] // 🎯 Forward to Python
        })
        .then(() => console.log("🐍 Python acknowledged!"))
        .catch(err => console.error("🚨 Node could not reach Python:", err.message));

        return res.json({ projectId: project.id });

    } catch (error: any) {
        console.error('💥 FINAL CATCH ERROR:', error.message);
        return res.status(500).json({ error: error.message });
    }
});

const PORT = Number(process.env.PORT) || 3000;
// 🔄 New route for real-time sparsity updates
app.post('/reprocess', reprocessLimiter, async (req, res) => {
    const { projectId, sparsity } = req.body;

    try {
        // 1. Fetch current project to get the erased_points we saved earlier
        const { data: project, error: fetchError } = await supabase
            .from('projects')
            .select('erased_points, remove_bg')
            .eq('id', projectId)
            .single();

        if (fetchError) throw fetchError;

        // 2. Update the status to processing
        await supabase
            .from('projects')
            .update({ 
                sparsity: Number(sparsity), 
                status: 'processing' 
            })
            .eq('id', projectId);

        // 3. Tell the Python worker to start again, INCLUDING the mask
        console.log(`🔄 Reprocessing Project: ${projectId} with mask...`);
        
        axios.post(`${PYTHON_WORKER_URL}/process`, {
            projectId: projectId,
            sparsity: Number(sparsity),
            removeBg: project.remove_bg, // Use existing setting
            erased_points: project.erased_points || [] // 🎯 DON'T FORGET THIS
        })
        .catch(err => console.error("Worker Trigger Error:", err.message));

        return res.json({ success: true });

    } catch (error: any) {
        console.error('Reprocess error:', error);
        return res.status(500).json({ error: error.message });
    }
});
app.delete('/account', async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const token = authHeader.split(' ')[1];

    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
        return res.status(401).json({ error: 'Invalid token' });
    }

    const userId = user.id;
    try {
        // Delete storage files belonging to this user
        const { data: projects } = await supabase
            .from('projects')
            .select('image_path')
            .eq('user_id', userId);

        if (projects && projects.length > 0) {
            const paths = projects.map((p: any) => p.image_path).filter(Boolean);
            if (paths.length > 0) {
                await supabase.storage.from('images').remove(paths);
            }
        }

        // Delete all projects
        await supabase.from('projects').delete().eq('user_id', userId);

        // Delete the auth user — requires service-role key
        await supabase.auth.admin.deleteUser(userId);

        return res.json({ success: true });
    } catch (error: any) {
        console.error('Account deletion error:', error);
        return res.status(500).json({ error: error.message });
    }
});

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.listen(PORT, () => console.log(`🚀 Node API listening on port ${PORT}`));