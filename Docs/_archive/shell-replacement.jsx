import React, { useState, useEffect } from 'react';

const ShellReplacement = () => {
  const [hoveredComponent, setHoveredComponent] = useState(null);
  const [showLauncher, setShowLauncher] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [currentTime, setCurrentTime] = useState(new Date());
  const [expandedApps, setExpandedApps] = useState(['Safari']);
  const [showCalendar, setShowCalendar] = useState(false);
  const [stagedFiles, setStagedFiles] = useState([
    { name: 'report.pdf', icon: '📄' },
    { name: 'screenshot.png', icon: '🖼️' },
  ]);
  const [clipboardHistory, setClipboardHistory] = useState([
    { type: 'text', content: 'https://github.com/example/repo', time: '2m' },
    { type: 'image', content: 'Screenshot', time: '5m' },
    { type: 'text', content: 'npm install sidebar-app', time: '12m' },
  ]);

  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const systemStatus = {
    wifi: true,
    bluetooth: true,
    battery: 87,
    volume: 65,
  };

  const pinnedApps = [
    { name: 'Finder', icon: '📁', color: '#4A90D9', running: true },
    { name: 'Safari', icon: '🧭', color: '#5AC8FA', running: true },
    { name: 'VS Code', icon: '💻', color: '#007ACC', running: true },
    { name: 'Terminal', icon: '⬛', color: '#1a1a1a', running: true },
    { name: 'Messages', icon: '💬', color: '#34C759', running: false },
    { name: 'Slack', icon: '💜', color: '#611f69', running: true },
    { name: 'Figma', icon: '🎨', color: '#a259ff', running: true },
    { name: 'Spotify', icon: '🎵', color: '#1DB954', running: false },
  ];

  const openApps = [
    { name: 'Finder', icon: '📁', windows: ['Downloads', 'Documents'] },
    { name: 'Safari', icon: '🧭', windows: ['GitHub - repo', 'Stack Overflow', 'Apple Developer'] },
    { name: 'VS Code', icon: '💻', windows: ['sidebar-app', 'pawkit-v2'] },
    { name: 'Figma', icon: '🎨', windows: ['Sidebar Design v2'] },
    { name: 'Terminal', icon: '⬛', windows: ['zsh - main'] },
    { name: 'Slack', icon: '💜', windows: ['Anthropic'] },
  ];

  const allApps = [
    { name: 'Finder', icon: '📁', category: 'System' },
    { name: 'Safari', icon: '🧭', category: 'Internet' },
    { name: 'Chrome', icon: '🌐', category: 'Internet' },
    { name: 'Firefox', icon: '🦊', category: 'Internet' },
    { name: 'VS Code', icon: '💻', category: 'Developer' },
    { name: 'Xcode', icon: '🔨', category: 'Developer' },
    { name: 'Terminal', icon: '⬛', category: 'Developer' },
    { name: 'iTerm', icon: '📟', category: 'Developer' },
    { name: 'Messages', icon: '💬', category: 'Social' },
    { name: 'Slack', icon: '💜', category: 'Social' },
    { name: 'Discord', icon: '🎮', category: 'Social' },
    { name: 'Figma', icon: '🎨', category: 'Design' },
    { name: 'Sketch', icon: '💎', category: 'Design' },
    { name: 'Photoshop', icon: '🖼️', category: 'Design' },
    { name: 'Spotify', icon: '🎵', category: 'Media' },
    { name: 'Music', icon: '🎶', category: 'Media' },
    { name: 'Photos', icon: '📷', category: 'Media' },
    { name: 'Notes', icon: '📝', category: 'Productivity' },
    { name: 'Reminders', icon: '☑️', category: 'Productivity' },
    { name: 'Calendar', icon: '📅', category: 'Productivity' },
    { name: 'System Settings', icon: '⚙️', category: 'System' },
    { name: 'Activity Monitor', icon: '📊', category: 'System' },
  ];

  const menuBarApps = [
    { name: '1Password', icon: '🔐' },
    { name: 'Bartender', icon: '🍸' },
    { name: 'CleanShot', icon: '📸' },
    { name: 'Raycast', icon: '🚀' },
  ];

  const filteredApps = allApps.filter(app => 
    app.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const getFlexValue = (componentName) => {
    if (!hoveredComponent) return 1;
    if (hoveredComponent === componentName) return 2.2;
    return 0.6;
  };

  const getOpacity = (componentName) => {
    if (!hoveredComponent) return 1;
    if (hoveredComponent === componentName) return 1;
    return 0.75;
  };

  const GlassPanel = ({ children, name, className = '' }) => (
    <div
      className={`relative overflow-hidden transition-all duration-300 ease-out ${className}`}
      style={{
        flex: getFlexValue(name),
        minHeight: '50px',
        background: 'linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.04) 100%)',
        backdropFilter: 'blur(40px) saturate(180%)',
        WebkitBackdropFilter: 'blur(40px) saturate(180%)',
        borderRadius: '14px',
        border: '1px solid rgba(255,255,255,0.15)',
        boxShadow: '0 8px 32px rgba(0,0,0,0.25), inset 0 1px 0 rgba(255,255,255,0.15)',
        opacity: getOpacity(name),
      }}
      onMouseEnter={() => setHoveredComponent(name)}
      onMouseLeave={() => setHoveredComponent(null)}
    >
      <div className="absolute inset-0 pointer-events-none" style={{
        background: 'radial-gradient(ellipse at top, rgba(255,255,255,0.08) 0%, transparent 60%)',
      }} />
      <div className="relative z-10 h-full flex flex-col">{children}</div>
    </div>
  );

  const Squircle = ({ app, size = 36, showIndicator = true }) => (
    <div className="relative group">
      <div
        className="flex items-center justify-center cursor-pointer transition-all duration-200 hover:scale-110"
        style={{
          width: size,
          height: size,
          borderRadius: size * 0.22,
          background: `linear-gradient(145deg, ${app.color || '#666'}, ${app.color || '#666'}cc)`,
          fontSize: size * 0.5,
          boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
        }}
        title={app.name}
      >
        {app.icon}
      </div>
      {showIndicator && app.running && (
        <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-white/80" />
      )}
    </div>
  );

  // Status Bar Component
  const StatusBar = () => {
    const isHovered = hoveredComponent === 'status';
    return (
      <GlassPanel name="status" className="p-2">
        <div className="flex items-center justify-between">
          <div 
            className="text-white font-light cursor-pointer"
            onClick={() => setShowCalendar(!showCalendar)}
          >
            <div className="text-lg">{currentTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
            {isHovered && (
              <div className="text-[10px] text-white/50">
                {currentTime.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })}
              </div>
            )}
          </div>
          <div className="flex items-center gap-2">
            <span className="text-sm" title="WiFi">📶</span>
            <span className="text-sm" title="Bluetooth">🔵</span>
            <span className="text-xs text-white/70">{systemStatus.battery}%</span>
            <span className="text-sm">🔋</span>
          </div>
        </div>
        {isHovered && (
          <>
            <div className="mt-2 pt-2 border-t border-white/10">
              <div className="text-[10px] text-white/40 mb-1">MENU BAR APPS</div>
              <div className="flex gap-2">
                {menuBarApps.map((app, i) => (
                  <div key={i} className="text-base cursor-pointer hover:scale-110 transition-transform" title={app.name}>
                    {app.icon}
                  </div>
                ))}
                <div className="text-white/30 text-xs">•••</div>
              </div>
            </div>
            <div className="mt-2 pt-2 border-t border-white/10 flex gap-2">
              <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10">
                🔒 Lock
              </button>
              <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10">
                😴 Sleep
              </button>
              <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10">
                ⚙️ Settings
              </button>
            </div>
          </>
        )}
      </GlassPanel>
    );
  };

  // Search Button Component
  const SearchButton = () => (
    <div
      className="p-3 rounded-xl cursor-pointer transition-all hover:bg-white/10"
      style={{
        background: 'linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.03) 100%)',
        border: '1px solid rgba(255,255,255,0.12)',
      }}
      onClick={() => setShowLauncher(true)}
    >
      <div className="flex items-center gap-2">
        <span className="text-white/40">🔍</span>
        <span className="text-xs text-white/40">Search...</span>
        <span className="ml-auto text-[10px] text-white/30 bg-white/10 px-1.5 py-0.5 rounded">⌘K</span>
      </div>
    </div>
  );

  // Pinned Apps Component
  const PinnedApps = () => {
    const isHovered = hoveredComponent === 'pinned';
    return (
      <GlassPanel name="pinned" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">APPS</div>
        <div className={`flex flex-wrap gap-2 ${isHovered ? 'justify-start' : 'justify-center'}`}>
          {pinnedApps.map((app, i) => (
            isHovered ? (
              <div key={i} className="flex items-center gap-2 w-full p-1.5 rounded-lg hover:bg-white/10 cursor-pointer group">
                <Squircle app={app} size={28} />
                <span className="text-xs text-white/80 flex-1">{app.name}</span>
                {app.running && <span className="w-1.5 h-1.5 rounded-full bg-green-400/80" />}
              </div>
            ) : (
              <Squircle key={i} app={app} size={34} />
            )
          ))}
        </div>
        {isHovered && (
          <div className="mt-2 pt-2 border-t border-white/10">
            <button 
              className="w-full text-[10px] text-white/50 hover:text-white/80 py-1 rounded hover:bg-white/10 transition-colors"
              onClick={() => setShowLauncher(true)}
            >
              + Add App
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  // Windows Component
  const WindowsComponent = () => {
    const isHovered = hoveredComponent === 'windows';
    return (
      <GlassPanel name="windows" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">WINDOWS</div>
        <div className="overflow-y-auto flex-1">
          {openApps.map((app, i) => (
            <div key={i} className="mb-0.5">
              <div 
                className="flex items-center gap-2 p-1.5 rounded-lg hover:bg-white/10 cursor-pointer transition-colors"
                onClick={() => setExpandedApps(prev => 
                  prev.includes(app.name) ? prev.filter(a => a !== app.name) : [...prev, app.name]
                )}
              >
                <span className="text-sm">{app.icon}</span>
                <span className="text-xs text-white/90 flex-1">{app.name}</span>
                <span className="text-[10px] text-white/40 bg-white/10 px-1.5 py-0.5 rounded">
                  {app.windows.length}
                </span>
              </div>
              {expandedApps.includes(app.name) && app.windows.map((win, j) => (
                <div 
                  key={j}
                  className="flex items-center gap-2 py-1 px-2 ml-5 rounded hover:bg-white/10 cursor-pointer text-[11px] text-white/60 transition-colors group"
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-white/30" />
                  <span className="truncate flex-1">{win}</span>
                  {isHovered && (
                    <div className="opacity-0 group-hover:opacity-100 flex gap-1">
                      <button className="text-white/40 hover:text-yellow-400">─</button>
                      <button className="text-white/40 hover:text-red-400">✕</button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          ))}
        </div>
        {isHovered && (
          <div className="mt-2 pt-2 border-t border-white/10 flex gap-1 justify-center flex-wrap">
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10">
              Group
            </button>
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10">
              Tile
            </button>
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10">
              Min All
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  // Clipboard Component
  const ClipboardComponent = () => {
    const isHovered = hoveredComponent === 'clipboard';
    return (
      <GlassPanel name="clipboard" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">CLIPBOARD</div>
        <div className="space-y-1 overflow-y-auto flex-1">
          {clipboardHistory.slice(0, isHovered ? 5 : 2).map((item, i) => (
            <div 
              key={i}
              className={`flex items-center gap-2 p-1.5 rounded-lg cursor-pointer transition-colors ${
                i === 0 ? 'bg-white/15' : 'hover:bg-white/10'
              }`}
            >
              <span className="text-sm">{item.type === 'text' ? '📋' : '🖼️'}</span>
              <span className="text-[11px] text-white/80 flex-1 truncate">{item.content}</span>
              <span className="text-[9px] text-white/30">{item.time}</span>
            </div>
          ))}
        </div>
      </GlassPanel>
    );
  };

  // Drop Zone Component
  const DropZoneComponent = () => {
    const [isDragOver, setIsDragOver] = useState(false);
    const isHovered = hoveredComponent === 'dropzone';
    return (
      <GlassPanel name="dropzone" className="p-2">
        <div className="flex items-center justify-between mb-2 px-1">
          <span className="text-[10px] text-white/40 font-medium">DROP ZONE</span>
          {stagedFiles.length > 0 && (
            <button className="text-[10px] text-red-400/70 hover:text-red-400" onClick={() => setStagedFiles([])}>
              Clear
            </button>
          )}
        </div>
        <div 
          className={`border border-dashed rounded-lg p-2 flex-1 overflow-y-auto transition-colors ${
            isDragOver ? 'border-blue-400 bg-blue-500/20' : 'border-white/20'
          }`}
          onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
          onDragLeave={() => setIsDragOver(false)}
          onDrop={() => setIsDragOver(false)}
        >
          {stagedFiles.length === 0 ? (
            <div className="text-center text-white/40 text-[10px] py-2">Drop files here</div>
          ) : (
            <div className="space-y-1">
              {stagedFiles.map((file, i) => (
                <div key={i} className="flex items-center gap-2 p-1.5 bg-white/10 rounded text-xs group cursor-grab" draggable>
                  <span>{file.icon}</span>
                  <span className="flex-1 truncate text-white/80">{file.name}</span>
                  <button 
                    className="text-white/30 hover:text-red-400 opacity-0 group-hover:opacity-100"
                    onClick={() => setStagedFiles(prev => prev.filter((_, idx) => idx !== i))}
                  >✕</button>
                </div>
              ))}
            </div>
          )}
        </div>
      </GlassPanel>
    );
  };

  // App Launcher Modal
  const LauncherModal = () => {
    const categories = [...new Set(allApps.map(a => a.category))];
    return (
      <div 
        className="fixed inset-0 z-50 flex items-start justify-center pt-24"
        style={{ background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(20px)' }}
        onClick={() => setShowLauncher(false)}
      >
        <div 
          className="w-[600px] rounded-2xl overflow-hidden"
          style={{
            background: 'linear-gradient(135deg, rgba(40,40,45,0.95) 0%, rgba(30,30,35,0.98) 100%)',
            border: '1px solid rgba(255,255,255,0.1)',
            boxShadow: '0 25px 80px rgba(0,0,0,0.5)',
          }}
          onClick={e => e.stopPropagation()}
        >
          {/* Search input */}
          <div className="p-4 border-b border-white/10">
            <div className="flex items-center gap-3 bg-white/5 rounded-xl px-4 py-3">
              <span className="text-white/40">🔍</span>
              <input
                type="text"
                placeholder="Search apps, files, settings..."
                className="flex-1 bg-transparent text-white outline-none placeholder:text-white/30"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                autoFocus
              />
              {searchQuery && (
                <button className="text-white/40 hover:text-white/80" onClick={() => setSearchQuery('')}>✕</button>
              )}
            </div>
          </div>

          {/* Results */}
          <div className="p-4 max-h-[60vh] overflow-y-auto">
            {searchQuery ? (
              // Search results
              <div className="space-y-1">
                {filteredApps.map((app, i) => (
                  <div 
                    key={i}
                    className="flex items-center gap-3 p-3 rounded-xl hover:bg-white/5 cursor-pointer group"
                  >
                    <span className="text-2xl">{app.icon}</span>
                    <div className="flex-1">
                      <div className="text-sm text-white">{app.name}</div>
                      <div className="text-[10px] text-white/40">{app.category}</div>
                    </div>
                    <button className="text-[10px] text-white/40 hover:text-white/80 opacity-0 group-hover:opacity-100 px-2 py-1 rounded bg-white/10">
                      + Pin
                    </button>
                  </div>
                ))}
                {filteredApps.length === 0 && (
                  <div className="text-center text-white/40 py-8">No results found</div>
                )}
              </div>
            ) : (
              // Category grid
              <div className="space-y-6">
                {categories.map(category => (
                  <div key={category}>
                    <h3 className="text-xs text-white/40 font-medium mb-3 px-1">{category.toUpperCase()}</h3>
                    <div className="grid grid-cols-6 gap-3">
                      {allApps.filter(a => a.category === category).map((app, i) => (
                        <div 
                          key={i}
                          className="flex flex-col items-center gap-1 p-3 rounded-xl hover:bg-white/5 cursor-pointer group"
                        >
                          <span className="text-3xl">{app.icon}</span>
                          <span className="text-[10px] text-white/70 truncate w-full text-center">{app.name}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="p-3 border-t border-white/10 flex items-center justify-between text-[10px] text-white/40">
            <div className="flex gap-4">
              <span>↑↓ Navigate</span>
              <span>↵ Open</span>
              <span>⌘↵ Pin to Sidebar</span>
            </div>
            <span>ESC to close</span>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-950 to-slate-900 relative overflow-hidden">
      {/* Background decoration */}
      <div className="absolute top-0 left-1/4 w-[600px] h-[600px] bg-purple-500/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-[500px] h-[500px] bg-blue-500/10 rounded-full blur-3xl" />
      
      {/* Main layout - no menu bar, no dock, just our sidebar */}
      <div className="flex h-screen">
        {/* Sidebar - full height */}
        <div className="w-52 p-2 flex flex-col gap-2 h-full">
          <StatusBar />
          <SearchButton />
          <PinnedApps />
          <WindowsComponent />
          <ClipboardComponent />
          <DropZoneComponent />
        </div>

        {/* Desktop area */}
        <div className="flex-1 p-6">
          {/* No menu bar! */}
          
          {/* Desktop icons */}
          <div className="grid grid-cols-8 gap-3">
            {[
              { icon: '📁', name: 'Projects' },
              { icon: '📄', name: 'Notes.txt' },
              { icon: '🖼️', name: 'Photo.png' },
              { icon: '📦', name: 'Archive.zip' },
              { icon: '💾', name: 'Backup' },
              { icon: '🎵', name: 'Music' },
            ].map((item, i) => (
              <div 
                key={i}
                className="flex flex-col items-center gap-1 p-2 rounded-xl hover:bg-white/10 cursor-pointer transition-all"
                draggable
              >
                <span className="text-3xl">{item.icon}</span>
                <span className="text-white/80 text-[10px]">{item.name}</span>
              </div>
            ))}
          </div>

          {/* Sample window */}
          <div 
            className="mt-8 rounded-xl overflow-hidden max-w-3xl"
            style={{
              background: 'linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.03) 100%)',
              backdropFilter: 'blur(20px)',
              border: '1px solid rgba(255,255,255,0.1)',
              boxShadow: '0 8px 32px rgba(0,0,0,0.3)',
            }}
          >
            <div className="h-10 bg-white/5 flex items-center px-4 gap-3 border-b border-white/10">
              <div className="flex gap-2">
                <div className="w-3 h-3 rounded-full bg-red-500/70 hover:bg-red-500 cursor-pointer" />
                <div className="w-3 h-3 rounded-full bg-yellow-500/70 hover:bg-yellow-500 cursor-pointer" />
                <div className="w-3 h-3 rounded-full bg-green-500/70 hover:bg-green-500 cursor-pointer" />
              </div>
              <span className="text-white/60 text-sm ml-2">Welcome to Sidebar</span>
            </div>
            <div className="p-6">
              <h2 className="text-white text-xl font-light mb-4">Your Mac, reimagined.</h2>
              <div className="space-y-3 text-sm text-white/60">
                <p>✓ Menu bar replaced with Status component</p>
                <p>✓ Dock replaced with Pinned Apps</p>
                <p>✓ Spotlight replaced with ⌘K launcher</p>
                <p>✓ Stage Manager replaced with Windows component</p>
                <p>✓ Plus: Clipboard history, Drop zone, Extensions</p>
              </div>
              <div className="mt-6 flex gap-3">
                <button className="px-4 py-2 rounded-lg bg-white/10 text-white text-sm hover:bg-white/20 transition-colors">
                  Configure Sidebar
                </button>
                <button 
                  className="px-4 py-2 rounded-lg bg-purple-500/30 text-purple-200 text-sm hover:bg-purple-500/40 transition-colors"
                  onClick={() => setShowLauncher(true)}
                >
                  Try ⌘K Search
                </button>
              </div>
            </div>
          </div>

          {/* Instructions */}
          <div className="mt-8 text-white/30 text-xs">
            <p>Click the search bar or press ⌘K to open the app launcher</p>
            <p>Hover over sidebar components to see them expand</p>
          </div>
        </div>
      </div>

      {/* Launcher modal */}
      {showLauncher && <LauncherModal />}
    </div>
  );
};

export default ShellReplacement;
