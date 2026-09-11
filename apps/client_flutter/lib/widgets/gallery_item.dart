import 'package:flutter/material.dart';

import '../models/dot_model.dart';
import '../models/project_model.dart';
import '../painters/dot_painter.dart';

typedef ProjectTapCallback = void Function(Map<String, dynamic> project);
typedef ProjectDeleteCallback = void Function(String id, String fileName);

class GalleryItem extends StatefulWidget {
  final Map<String, dynamic> project;
  final bool isActive;
  final bool isGameMenu;
  final ProjectTapCallback onTap;
  final ProjectDeleteCallback? onDelete;

  const GalleryItem({
    super.key,
    required this.project,
    required this.isActive,
    required this.isGameMenu,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<GalleryItem> createState() => _GalleryItemState();
}

class _GalleryItemState extends State<GalleryItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final p = Project.fromMap(widget.project);
    final cs = Theme.of(context).colorScheme;
    final bool inProgress = p.lastIndex > 0 && p.lastIndex < p.dotCount;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: widget.isActive
            ? cs.primary.withValues(alpha: 0.12)
            : _isHovered
                ? cs.surface.withValues(alpha: 0.6)
                : Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(widget.project),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: _buildIcon(p),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + stars + progress
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          color: widget.isActive ? cs.primary : cs.onSurface,
                          fontWeight: widget.isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildMiniStar(p.easyCleared, Colors.amber),
                          _buildMiniStar(p.mediumCleared, Colors.orange),
                          _buildMiniStar(p.hardCleared, Colors.redAccent),
                          if (inProgress && widget.isGameMenu) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${p.lastIndex}/${p.dotCount} dots',
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (inProgress && widget.isGameMenu)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: LinearProgressIndicator(
                            value: p.dotCount > 0
                                ? p.lastIndex / p.dotCount
                                : 0.0,
                            minHeight: 2,
                            color: cs.primary,
                            backgroundColor:
                                cs.primary.withValues(alpha: 0.2),
                          ),
                        ),
                    ],
                  ),
                ),

                // Delete button — hidden for featured puzzles (onDelete == null)
                if (widget.onDelete != null && (!widget.isGameMenu || _isHovered))
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    onPressed: () =>
                        widget.onDelete!(p.id, p.imagePath ?? ''),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStar(bool cleared, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Icon(
        cleared ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 14,
        color: cleared ? color : color.withValues(alpha: 0.25),
      ),
    );
  }

  Widget _buildIcon(Project p) {
    if (p.imagePath != null && p.imagePath!.isNotEmpty) {
      return Image.network(
        p.imagePath!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDotThumbnail(p),
      );
    }
    return _buildDotThumbnail(p);
  }

  Widget _buildDotThumbnail(Project p) {
    final rawDots = p.dots.isNotEmpty ? p.dots : (p.dotsEasy ?? const []);
    if (rawDots.isEmpty) {
      return Container(
        color: Colors.black26,
        child: const Icon(Icons.grid_on_rounded, size: 28, color: Colors.white54),
      );
    }
    final dotList = rawDots
        .whereType<Map<String, dynamic>>()
        .map(Dot.fromMap)
        .toList();
    return Container(
      color: Colors.black54,
      child: CustomPaint(
        size: const Size(56, 56),
        painter: ThumbnailDotPainter(dotList),
      ),
    );
  }
}
