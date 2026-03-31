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

// Layout dimensions per mode
const LAYOUT = {
  grid:    { cardW: 280, cardH: 260, gapX: 20, gapY: 20, columns: 4, inset: 20, headerH: 60 },
  list:    { cardW: 520, cardH: 52,  gapX: 0,  gapY: 6,  columns: 1, inset: 20, headerH: 60 },
  masonry: { cardW: 280, gapX: 14, gapY: 14, columns: 3, inset: 20, headerH: 60 },
};

/**
 * Reposition child nodes within a folder based on layout mode.
 * For grid/list: uses fixed dimensions. For masonry: uses measured node heights.
 * Returns updated nodes array.
 */
function layoutFolderChildren(allNodes, folderId, mode, reactFlowInstance) {
  const L = LAYOUT[mode] || LAYOUT.grid;
  const children = allNodes.filter(n => n.parentId === folderId);
  if (children.length === 0) return { nodes: allNodes, folderWidth: 300, folderHeight: 200 };

  const childIds = new Set(children.map(n => n.id));
  const layoutClass = `layout-${mode}`;

  let positions;
  if (mode === 'masonry') {
    // Use measured heights from React Flow's internal node measurements
    const rfNodes = reactFlowInstance ? reactFlowInstance.getNodes() : [];
    const measuredMap = new Map();
    for (const rfn of rfNodes) {
      if (rfn.measured?.height) {
        measuredMap.set(rfn.id, rfn.measured.height);
      }
    }

    const colHeights = new Array(L.columns).fill(L.headerH);
    positions = children.map((child) => {
      const shortestCol = colHeights.indexOf(Math.min(...colHeights));
      const x = L.inset + shortestCol * (L.cardW + L.gapX);
      const y = colHeights[shortestCol];
      // Use measured height if available, otherwise generous fallback
      const h = measuredMap.get(child.id) || 320;
      colHeights[shortestCol] = y + h + L.gapY;
      return { id: child.id, x, y, h };
    });
  } else {
    // Grid or List: simple row/column layout with fixed heights
    const cardH = L.cardH;
    positions = children.map((child, i) => {
      const col = i % L.columns;
      const row = Math.floor(i / L.columns);
      return {
        id: child.id,
        x: L.inset + col * (L.cardW + L.gapX),
        y: L.headerH + row * (cardH + L.gapY),
        h: cardH,
      };
    });
  }

  // Calculate folder size to fit all children
  const maxX = Math.max(...positions.map(p => p.x + L.cardW)) + L.inset;
  const maxY = Math.max(...positions.map(p => p.y + p.h)) + L.inset + 20;
  const folderWidth = Math.max(300, maxX);
  const folderHeight = Math.max(200, maxY);

  const posMap = new Map(positions.map(p => [p.id, { x: p.x, y: p.y }]));

  const updatedNodes = allNodes.map(n => {
    if (childIds.has(n.id)) {
      const pos = posMap.get(n.id);
      return {
        ...n,
        position: pos || n.position,
        data: { ...n.data, layoutClass },
        className: layoutClass,
      };
    }
    if (n.id === folderId) {
      return {
        ...n,
        data: { ...n.data, layoutMode: mode },
        style: { width: folderWidth, height: folderHeight },
      };
    }
    return n;
  });

  return { nodes: updatedNodes, folderWidth, folderHeight };
}

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
          nodeType: n.type,
          position: n.position,
          size: { width: n.measured?.width || 280, height: n.measured?.height || 200 },
          style: n.style || null,
          parentNode: n.parentId || null,
          metadata: n.data,
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
      loadCanvasBase64(base64String) {
        try {
          // Decode base64 with proper UTF-8 handling (atob alone mangles multi-byte chars)
          const binaryString = atob(base64String);
          const bytes = Uint8Array.from(binaryString, c => c.charCodeAt(0));
          const jsonString = new TextDecoder().decode(bytes);
          this.loadCanvas(jsonString);
        } catch (err) {
          postMessage('canvasError', JSON.stringify({
            message: `loadCanvasBase64 failed: ${err.message}`,
            stack: err.stack,
          }));
        }
      },

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
       * Pan/zoom to a specific folder group node.
       */
      panToGroup(groupId) {
        const node = reactFlowInstance.getNodes().find(n => n.id === groupId);
        if (node) {
          const width = node.measured?.width || node.style?.width || 800;
          const height = node.measured?.height || node.style?.height || 600;
          reactFlowInstance.fitBounds(
            { x: node.position.x, y: node.position.y, width, height },
            { padding: 0.1, duration: 400 }
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
       * Set the layout mode for a folder's children.
       * Two-pass for masonry: apply classes first, then measure and reposition.
       */
      setFolderLayout(folderId, mode) {
        const layoutClass = `layout-${mode}`;

        if (mode === 'masonry') {
          // Pass 1: Apply layout classes so cards render at natural height,
          // and spread cards vertically so React Flow measures them properly
          setNodes(prev => {
            const children = prev.filter(n => n.parentId === folderId);
            const childIds = new Set(children.map(n => n.id));
            let y = 60;
            return prev.map(n => {
              if (childIds.has(n.id)) {
                const pos = { x: 20, y };
                y += 400; // spread out so nothing overlaps during measurement
                return { ...n, position: pos, data: { ...n.data, layoutClass }, className: layoutClass };
              }
              if (n.id === folderId) {
                return { ...n, data: { ...n.data, layoutMode: mode }, style: { width: 920, height: y + 100 } };
              }
              return n;
            });
          });

          // Pass 2: After render, measure actual heights and do real masonry layout
          setTimeout(() => {
            setNodes(prev => {
              const result = layoutFolderChildren(prev, folderId, mode, reactFlowInstance);
              return result.nodes;
            });
            // Pass 3: Re-measure after images may have loaded for final accuracy
            setTimeout(() => {
              setNodes(prev => {
                const result = layoutFolderChildren(prev, folderId, mode, reactFlowInstance);
                return result.nodes;
              });
              scheduleSave();
            }, 500);
          }, 250);
        } else {
          // Grid/List: single pass with fixed heights
          setNodes(prev => {
            const result = layoutFolderChildren(prev, folderId, mode, reactFlowInstance);
            return result.nodes;
          });
          scheduleSave();
        }
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
