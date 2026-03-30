import React, { memo } from 'react';
import { Handle, Position } from '@xyflow/react';

/**
 * Custom React Flow node that renders a Cider bookmark card.
 * Matches the native SwiftUI BookmarkCard styling:
 * - Thumbnail area with favicon fallback
 * - Title (2 lines max)
 * - Domain + relative time
 * - Tag pills
 */
const BookmarkCardNode = memo(({ data, selected }) => {
  const {
    title = 'Untitled',
    url = '',
    domain = '',
    favicon = '',
    thumbnail = '',
    tags = [],
    timeAgo = '',
    hasAISummary = false,
  } = data;

  const handleClick = () => {
    postMessage('itemClicked', JSON.stringify({
      uuid: data.itemID,
      type: 'bookmark',
    }));
  };

  return (
    <div
      className={`bookmark-card ${selected ? 'selected' : ''}`}
      onClick={handleClick}
    >
      {/* Connection handles (hidden visually, used for edges) */}
      <Handle type="target" position={Position.Top} className="card-handle" />
      <Handle type="source" position={Position.Bottom} className="card-handle" />

      {/* Thumbnail area */}
      <div className="card-thumbnail">
        {thumbnail ? (
          <img src={thumbnail} alt="" className="card-thumbnail-img" draggable={false} />
        ) : (
          <div className="card-thumbnail-fallback">
            {favicon ? (
              <img src={favicon} alt="" className="card-favicon-large" draggable={false} />
            ) : (
              <div className="card-favicon-placeholder">
                {domain ? domain.charAt(0).toUpperCase() : '?'}
              </div>
            )}
          </div>
        )}
        {hasAISummary && (
          <div className="card-ai-badge" title="AI summary available">✦</div>
        )}
      </div>

      {/* Card content */}
      <div className="card-content">
        <div className="card-title">{title}</div>
        <div className="card-meta">
          {favicon && <img src={favicon} alt="" className="card-favicon" draggable={false} />}
          <span className="card-domain">{domain}</span>
          {timeAgo && (
            <>
              <span className="card-separator">•</span>
              <span className="card-time">{timeAgo}</span>
            </>
          )}
        </div>
        {tags.length > 0 && (
          <div className="card-tags">
            {tags.map((tag, i) => (
              <span
                key={i}
                className="card-tag"
                style={{
                  '--tag-color': tag.color || '#888',
                }}
              >
                <span className="card-tag-dot" />
                {tag.name}
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
});

BookmarkCardNode.displayName = 'BookmarkCardNode';

function postMessage(name, data) {
  const handler = window.webkit?.messageHandlers?.[name];
  if (handler) {
    handler.postMessage(data ?? '');
  }
}

export default BookmarkCardNode;
