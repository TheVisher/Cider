import React, { useRef, useCallback, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Excalidraw } from '@excalidraw/excalidraw';

// Debounce timer for scene change saves
let saveTimer = null;
const SAVE_DEBOUNCE_MS = 1500;

function postMessage(name, data) {
  const handler = window.webkit?.messageHandlers?.[name];
  if (handler) {
    handler.postMessage(data ?? '');
  }
}

function App() {
  const excalidrawAPIRef = useRef(null);
  const [theme, setTheme] = useState('dark');
  const isLoadingScene = useRef(false);

  const handleChange = useCallback((elements, appState) => {
    // Don't fire save events while we're programmatically loading a scene
    if (isLoadingScene.current) return;

    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      const api = excalidrawAPIRef.current;
      if (!api) return;

      const scene = {
        type: 'excalidraw',
        version: 2,
        source: 'cider',
        elements: api.getSceneElements(),
        appState: {
          viewBackgroundColor: appState.viewBackgroundColor || 'transparent',
        },
        files: api.getFiles(),
      };

      postMessage('sceneChanged', JSON.stringify(scene));
    }, SAVE_DEBOUNCE_MS);
  }, []);

  // Expose bridge API for Swift
  useEffect(() => {
    window.excalidrawBridge = {
      loadScene(jsonString) {
        const api = excalidrawAPIRef.current;
        if (!api) return;

        try {
          isLoadingScene.current = true;
          const scene = JSON.parse(jsonString);
          api.updateScene({
            elements: scene.elements || [],
          });

          if (scene.files && Object.keys(scene.files).length > 0) {
            api.addFiles(Object.values(scene.files));
          }

          // Clear loading flag after React processes the update
          requestAnimationFrame(() => {
            isLoadingScene.current = false;
          });
        } catch (err) {
          isLoadingScene.current = false;
          postMessage('excalidrawError', `loadScene failed: ${err.message}`);
        }
      },

      getScene() {
        const api = excalidrawAPIRef.current;
        if (!api) return '{}';

        const scene = {
          type: 'excalidraw',
          version: 2,
          source: 'cider',
          elements: api.getSceneElements(),
          appState: {
            viewBackgroundColor: 'transparent',
          },
          files: api.getFiles(),
        };

        return JSON.stringify(scene);
      },

      setTheme(newTheme) {
        setTheme(newTheme === 'light' ? 'light' : 'dark');
      },

      resetScene() {
        const api = excalidrawAPIRef.current;
        if (!api) return;
        isLoadingScene.current = true;
        api.resetScene();
        requestAnimationFrame(() => {
          isLoadingScene.current = false;
        });
      },
    };

    postMessage('excalidrawReady');

    return () => {
      delete window.excalidrawBridge;
    };
  }, []);

  return (
    <div style={{ width: '100%', height: '100%' }}>
      <Excalidraw
        excalidrawAPI={(api) => { excalidrawAPIRef.current = api; }}
        theme={theme}
        onChange={handleChange}
        initialData={{
          appState: {
            viewBackgroundColor: 'transparent',
          },
        }}
        UIOptions={{
          canvasActions: {
            changeViewBackgroundColor: false,
            loadScene: false,
            saveToActiveFile: false,
            export: false,
          },
        }}
      />
    </div>
  );
}

const root = createRoot(document.getElementById('root'));
root.render(<App />);
