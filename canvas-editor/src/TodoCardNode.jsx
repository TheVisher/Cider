import React, { memo } from 'react';
import { Handle, Position } from '@xyflow/react';

/**
 * Custom React Flow node for Cider todos.
 * Shows title, priority, due date, completion status, and checklist progress.
 */
const TodoCardNode = memo(({ data, selected }) => {
  const {
    title = 'Untitled Todo',
    priority = null,
    isCompleted = false,
    dueDate = '',
    timeAgo = '',
    checklistTotal = 0,
    checklistDone = 0,
    tags = [],
  } = data;

  const priorityColor = {
    high: '#ff453a',
    medium: '#ff9f0a',
    low: '#64d2ff',
  }[priority] || null;

  const handleClick = () => {
    postMessage('itemClicked', JSON.stringify({
      uuid: data.itemID,
      type: 'todo',
    }));
  };

  return (
    <div
      className={`todo-card ${selected ? 'selected' : ''} ${isCompleted ? 'completed' : ''}`}
      onClick={handleClick}
      style={priorityColor ? { '--priority-color': priorityColor } : {}}
    >
      <Handle type="target" position={Position.Top} className="card-handle" />
      <Handle type="source" position={Position.Bottom} className="card-handle" />

      <div className="card-content">
        {/* Title row with checkbox */}
        <div className="todo-card-title-row">
          <div className={`todo-card-checkbox ${isCompleted ? 'checked' : ''}`}>
            {isCompleted && <span>✓</span>}
          </div>
          <div className={`card-title ${isCompleted ? 'todo-done' : ''}`}>{title}</div>
        </div>

        {/* Priority + due date row */}
        <div className="card-meta">
          {priority && (
            <span className="todo-card-priority" style={{ color: priorityColor }}>
              {priority.charAt(0).toUpperCase() + priority.slice(1)}
            </span>
          )}
          {priority && (dueDate || timeAgo) && <span className="card-separator">•</span>}
          {dueDate && <span className="card-domain">{dueDate}</span>}
          {!dueDate && timeAgo && <span className="card-time">{timeAgo}</span>}
        </div>

        {/* Checklist progress */}
        {checklistTotal > 0 && (
          <div className="todo-card-progress">
            <div className="todo-card-progress-bar">
              <div
                className="todo-card-progress-fill"
                style={{ width: `${(checklistDone / checklistTotal) * 100}%` }}
              />
            </div>
            <span className="todo-card-progress-text">{checklistDone}/{checklistTotal}</span>
          </div>
        )}

        {/* Tags */}
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

TodoCardNode.displayName = 'TodoCardNode';

function postMessage(name, data) {
  const handler = window.webkit?.messageHandlers?.[name];
  if (handler) {
    handler.postMessage(data ?? '');
  }
}

export default TodoCardNode;
