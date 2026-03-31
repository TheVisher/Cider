import React, { memo } from 'react';
import { Handle, Position } from '@xyflow/react';

/**
 * Custom React Flow node for Cider notes.
 * Shows title, content preview, word count, and tags.
 */
const NoteCardNode = memo(({ data, selected }) => {
  const {
    title = 'Untitled Note',
    preview = '',
    wordCount = 0,
    timeAgo = '',
    tags = [],
    isPinned = false,
  } = data;

  const handleClick = () => {
    postMessage('itemClicked', JSON.stringify({
      uuid: data.itemID,
      type: 'note',
    }));
  };

  return (
    <div
      className={`note-card ${selected ? 'selected' : ''}`}
      onClick={handleClick}
    >
      <Handle type="target" position={Position.Top} className="card-handle" />
      <Handle type="source" position={Position.Bottom} className="card-handle" />

      {/* Note icon header */}
      <div className="note-card-header">
        <span className="note-card-icon">📝</span>
        {isPinned && <span className="note-card-pin">📌</span>}
      </div>

      {/* Content */}
      <div className="card-content">
        <div className="card-title">{title}</div>
        <div className="note-card-preview">{preview}</div>
        <div className="card-meta">
          <span className="card-domain">{wordCount} words</span>
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
                style={{ '--tag-color': tag.color || '#888' }}
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

NoteCardNode.displayName = 'NoteCardNode';

function postMessage(name, data) {
  const handler = window.webkit?.messageHandlers?.[name];
  if (handler) {
    handler.postMessage(data ?? '');
  }
}

export default NoteCardNode;
