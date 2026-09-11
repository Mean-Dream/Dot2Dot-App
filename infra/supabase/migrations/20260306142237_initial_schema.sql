-- 1. Projects Table
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Gallery Items
CREATE TABLE gallery_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects ON DELETE CASCADE,
  url TEXT NOT NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Entitlements (What a user owns/can do)
CREATE TABLE entitlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users UNIQUE NOT NULL,
  tier TEXT DEFAULT 'free',
  features JSONB,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Credits Ledger (Tracking balance)
CREATE TABLE credits_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users NOT NULL,
  amount INT NOT NULL, -- positive for purchase, negative for use
  transaction_type TEXT, -- 'purchase', 'usage', 'refund'
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Exports
CREATE TABLE exports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects ON DELETE CASCADE,
  status TEXT DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
  storage_path TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);