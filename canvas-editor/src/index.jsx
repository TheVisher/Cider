import React, { useCallback, useRef, useState, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  useReactFlow,
  ReactFlowProvider,
} from '@xyflow/react';

import BookmarkCardNode from './BookmarkCardNode';
import NoteCardNode from './NoteCardNode';
import TodoCardNode from './TodoCardNode';
import FolderGroupNode from './FolderGroupNode';

// Custom node types registry
const nodeTypes = {
  bookmarkCard: BookmarkCardNode,
  noteCard: NoteCardNode,
  todoCard: TodoCardNode,
  folderGroup: FolderGroupNode,
};

// Debounce timer for canvas change saves
let saveTimer = null;
const SAVE_DEBOUNCE_MS = 1500;

function postMessage(name, data) {
  const handler = window.webkit?.messageHandlers?.[name];
  if (handler) {
    handler.postMessage(data ?? '');
  }
}

function CanvasApp() {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [theme, setTheme] = useState('dark');
  const reactFlowInstance = useReactFlow();
  const isLoadingRef = useRef(false);

  // Debounced save — fires after nodes/edges change
  const handleNodesChange = useCallback((changes) => {
    if (isLoadingRef.current) {
      onNodesChange(changes);
      return;
    }
    onNodesChange(changes);
    scheduleSave();
  }, [onNodesChange]);

  const handleEdgesChange = useCallback((changes) => {
    if (isLoadingRef.current) {
      onEdgesChange(changes);
      return;
    }
    onEdgesChange(changes);
    scheduleSave();
  }, [onEdgesChange]);

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      const currentNodes = reactFlowInstance.getNodes();
      const currentEdges = reactFlowInstance.getEdges();
      const viewport = reactFlowInstance.getViewport();

      const canvasData = {
        version: 1,
        nodes: currentNodes.map(n => ({
          id: n.id,
          itemID: n.data?.itemID,
          itemType: n.data?.itemType || 'bookmark',
          position: n.position,
          size: { width: n.measured?.width || 280, height: n.measured?.height || 200 },
          parentNode: n.parentId || null,
        })),
        edges: currentEdges.map(e => ({
          id: e.id,
          source: e.source,
          target: e.target,
          label: e.label || '',
        })),
        viewport,
      };

      postMessage('canvasChanged', JSON.stringify(canvasData));
    }, SAVE_DEBOUNCE_MS);
  }

  // Handle node click — notify Swift
  const onNodeClick = useCallback((_event, node) => {
    if (node.data?.itemID) {
      postMessage('itemClicked', JSON.stringify({
        uuid: node.data.itemID,
        type: node.data.itemType || 'bookmark',
      }));
    }
  }, []);

  // Handle node double-click — notify Swift for editing
  const onNodeDoubleClick = useCallback((_event, node) => {
    if (node.data?.itemID) {
      postMessage('itemDoubleClicked', JSON.stringify({
        uuid: node.data.itemID,
        type: node.data.itemType || 'bookmark',
      }));
    }
  }, []);

  // Expose bridge API for Swift
  React.useEffect(() => {
    window.canvasBridge = {
      /**
       * Load a full canvas state from JSON.
       */
      loadCanvas(jsonString) {
        try {
          isLoadingRef.current = true;
          const data = JSON.parse(jsonString);

          const loadedNodes = (data.nodes || []).map(n => {
            const node = {
              id: n.id,
              type: n.nodeType || 'bookmarkCard',
              position: n.position || { x: 0, y: 0 },
              data: {
                itemID: n.itemID,
                itemType: n.itemType || 'bookmark',
                ...n.metadata,
              },
            };
            // Parent-child relationship
            if (n.parentNode) {
              node.parentId = n.parentNode;
              node.extent = 'parent';
            }
            // Style (used for folder group sizing)
            if (n.style) {
              node.style = n.style;
            }
            return node;
          });

          const loadedEdges = (data.edges || []).map(e => ({
            id: e.id,
            source: e.source,
            target: e.target,
            label: e.label || undefined,
            type: 'default',
          }));

          setNodes(loadedNodes);
          setEdges(loadedEdges);

          if (data.viewport) {
            setTimeout(() => {
              reactFlowInstance.setViewport(data.viewport);
              isLoadingRef.current = false;
            }, 50);
          } else {
            setTimeout(() => {
              reactFlowInstance.fitView({ padding: 0.2 });
              isLoadingRef.current = false;
            }, 50);
          }
        } catch (err) {
          isLoadingRef.current = false;
          postMessage('canvasError', JSON.stringify({
            message: `loadCanvas failed: ${err.message}`,
            stack: err.stack,
          }));
        }
      },

      /**
       * Get the current canvas state as JSON.
       */
      getCanvas() {
        const currentNodes = reactFlowInstance.getNodes();
        const currentEdges = reactFlowInstance.getEdges();
        const viewport = reactFlowInstance.getViewport();

        return JSON.stringify({
          version: 1,
          nodes: currentNodes.map(n => ({
            id: n.id,
            itemID: n.data?.itemID,
            itemType: n.data?.itemType || 'bookmark',
            position: n.position,
            size: { width: n.measured?.width || 280, height: n.measured?.height || 200 },
            parentNode: n.parentId || null,
            nodeType: n.type,
            style: n.style || null,
            metadata: n.data,
          })),
          edges: currentEdges.map(e => ({
            id: e.id,
            source: e.source,
            target: e.target,
            label: e.label || '',
          })),
          viewport,
        });
      },

      /**
       * Place a single item on the canvas at the given position.
       */
      placeItem(uuid, nodeType, x, y, metadataJSON) {
        const metadata = metadataJSON ? JSON.parse(metadataJSON) : {};
        const nodeId = `node-${uuid}`;

        const newNode = {
          id: nodeId,
          type: nodeType || 'bookmarkCard',
          position: { x, y },
          data: {
            itemID: uuid,
            itemType: nodeType === 'noteCard' ? 'note' : nodeType === 'todoCard' ? 'todo' : 'bookmark',
            ...metadata,
          },
        };

        setNodes(prev => {
          // Replace if exists, otherwise add
          const existing = prev.findIndex(n => n.data?.itemID === uuid);
          if (existing >= 0) {
            const updated = [...prev];
            updated[existing] = { ...updated[existing], ...newNode, id: updated[existing].id };
            return updated;
          }
          return [...prev, newNode];
        });

        scheduleSave();
      },

      /**
       * Place a folder group node on the canvas.
       */
      placeFolder(id, x, y, width, height, metadataJSON) {
        const metadata = metadataJSON ? JSON.parse(metadataJSON) : {};
        const newNode = {
          id,
          type: 'folderGroup',
          position: { x, y },
          style: { width, height },
          data: { ...metadata },
        };
        setNodes(prev => {
          const existing = prev.findIndex(n => n.id === id);
          if (existing >= 0) {
            const updated = [...prev];
            updated[existing] = { ...updated[existing], ...newNode };
            return updated;
          }
          return [...prev, newNode];
        });
      },

      /**
       * Place an item as a child of a folder group.
       */
      placeChildItem(uuid, nodeType, x, y, parentId, metadataJSON) {
        const metadata = metadataJSON ? JSON.parse(metadataJSON) : {};
        const nodeId = `node-${uuid}`;
        const newNode = {
          id: nodeId,
          type: nodeType || 'bookmarkCard',
          position: { x, y },
          parentId,
          extent: 'parent',
          data: {
            itemID: uuid,
            itemType: nodeType === 'noteCard' ? 'note' : nodeType === 'todoCard' ? 'todo' : 'bookmark',
            ...metadata,
          },
        };
        setNodes(prev => {
          const existing = prev.findIndex(n => n.data?.itemID === uuid);
          if (existing >= 0) {
            const updated = [...prev];
            updated[existing] = { ...updated[existing], ...newNode, id: updated[existing].id };
            return updated;
          }
          return [...prev, newNode];
        });
      },

      /**
       * Remove an item from the canvas.
       */
      removeItem(uuid) {
        setNodes(prev => prev.filter(n => n.data?.itemID !== uuid));
        scheduleSave();
      },

      /**
       * Update an existing item's metadata (e.g., title changed, new tags).
       */
      updateItemMetadata(uuid, metadataJSON) {
        const metadata = metadataJSON ? JSON.parse(metadataJSON) : {};
        setNodes(prev => prev.map(n => {
          if (n.data?.itemID === uuid) {
            return { ...n, data: { ...n.data, ...metadata } };
          }
          return n;
        }));
      },

      /**
       * Pan/zoom to fit a specific item.
       */
      panToItem(uuid) {
        const node = reactFlowInstance.getNodes().find(n => n.data?.itemID === uuid);
        if (node) {
          reactFlowInstance.setCenter(
            node.position.x + 140,
            node.position.y + 100,
            { zoom: 1, duration: 300 }
          );
        }
      },

      /**
       * Zoom to fit all nodes.
       */
      fitAll() {
        reactFlowInstance.fitView({ padding: 0.2, duration: 300 });
      },

      /**
       * Add an edge between two items.
       */
      addEdge(sourceUuid, targetUuid, label) {
        const sourceNode = reactFlowInstance.getNodes().find(n => n.data?.itemID === sourceUuid);
        const targetNode = reactFlowInstance.getNodes().find(n => n.data?.itemID === targetUuid);
        if (sourceNode && targetNode) {
          const edgeId = `edge-${sourceNode.id}-${targetNode.id}`;
          setEdges(prev => [...prev, {
            id: edgeId,
            source: sourceNode.id,
            target: targetNode.id,
            label: label || undefined,
            type: 'default',
          }]);
          scheduleSave();
        }
      },

      /**
       * Toggle folder collapse — hide/show child nodes.
       */
      toggleFolderCollapse(folderId, collapsed) {
        setNodes(prev => prev.map(n => {
          // Update the folder node's collapsed state + size
          if (n.id === folderId) {
            if (collapsed) {
              // Save expanded size before collapsing
              return {
                ...n,
                data: {
                  ...n.data,
                  collapsed,
                  _expandedStyle: n.style,
                },
                style: { width: 'auto', height: 44 },
              };
            } else {
              // Restore expanded size
              return {
                ...n,
                data: { ...n.data, collapsed },
                style: n.data._expandedStyle || n.style,
              };
            }
          }
          // Hide/show child nodes
          if (n.parentId === folderId) {
            return { ...n, hidden: collapsed };
          }
          return n;
        }));
        scheduleSave();
      },

      /**
       * Set the color theme.
       */
      setTheme(newTheme) {
        setTheme(newTheme === 'light' ? 'light' : 'dark');
        document.documentElement.setAttribute('data-theme', newTheme === 'light' ? 'light' : 'dark');
      },
    };

    // Signal ready to Swift
    postMessage('canvasReady', '');

    return () => {
      delete window.canvasBridge;
    };
  }, [reactFlowInstance, setNodes, setEdges]);

  const isDark = theme === 'dark';
  const containerRef = useRef(null);

  // Track zoom level and set CSS classes for LOD (level of detail)
  const onViewportChange = useCallback((viewport) => {
    const el = containerRef.current;
    if (!el) return;
    const zoom = viewport.zoom;
    el.classList.toggle('zoom-tiny', zoom < 0.25);
    el.classList.toggle('zoom-small', zoom >= 0.25 && zoom < 0.5);
    el.classList.toggle('zoom-medium', zoom >= 0.5 && zoom < 0.8);
  }, []);

  return (
    <div ref={containerRef} className={`canvas-container ${isDark ? 'dark' : 'light'}`}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={handleNodesChange}
        onEdgesChange={handleEdgesChange}
        onNodeClick={onNodeClick}
        onNodeDoubleClick={onNodeDoubleClick}
        onViewportChange={onViewportChange}
        nodeTypes={nodeTypes}
        fitView
        minZoom={0.1}
        maxZoom={2}
        defaultEdgeOptions={{ type: 'default', animated: false }}
        proOptions={{ hideAttribution: true }}
      >
        <Background
          color={isDark ? '#333' : '#ccc'}
          gap={20}
          size={1}
        />
        <Controls
          showInteractive={false}
          position="bottom-right"
        />
        <MiniMap
          nodeColor={() => isDark ? '#555' : '#ddd'}
          maskColor={isDark ? 'rgba(0,0,0,0.6)' : 'rgba(255,255,255,0.6)'}
          position="bottom-left"
        />
      </ReactFlow>
    </div>
  );
}

// Wrap in provider so useReactFlow() works
function App() {
  return (
    <ReactFlowProvider>
      <CanvasApp />
    </ReactFlowProvider>
  );
}

const root = createRoot(document.getElementById('root'));
root.render(<App />);
