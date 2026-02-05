import React, { useState } from 'react';

const PawkitIntegration = () => {
  const [hoveredComponent, setHoveredComponent] = useState(null);
  const [showSaveModal, setShowSaveModal] = useState(false);
  const [saveItem, setSaveItem] = useState(null);
  const [pawkitSearch, setPawkitSearch] = useState('');
  
  const [recentPawkitItems, setRecentPawkitItems] = useState([
    { type: 'bookmark', title: 'React Server Components Guide', url: 'https://react.dev/...', tags: ['dev', 'react'], time: '2h' },
    { type: 'note', title: 'Sidebar feature ideas', preview: 'Extension system, drop zone...', tags: ['projects', 'sidebar'], time: '5h' },
    { type: 'file', title: 'Q4 Planning.pdf', size: '2.4 MB', tags: ['work'], time: '1d' },
    { type: 'bookmark', title: 'SwiftUI Layout Guide', url: 'https://developer.apple.com/...', tags: ['dev', 'swift'], time: '2d' },
  ]);

  const [pawkitTags, setPawkitTags] = useState([
    { name: 'dev', count: 47, color: '#3b82f6' },
    { name: 'work', count: 23, color: '#10b981' },
    { name: 'projects', count: 18, color: '#8b5cf6' },
    { name: 'reading', count: 31, color: '#f59e0b' },
    { name: 'reference', count: 56, color: '#ec4899' },
  ]);

  const [inboxItems, setInboxItems] = useState([
    { type: 'bookmark', title: 'Unsorted article...', time: '10m' },
    { type: 'file', title: 'download.pdf', time: '1h' },
  ]);

  const [stagedFiles, setStagedFiles] = useState([
    { name: 'architecture-diagram.png', icon: '🖼️' },
    { name: 'meeting-notes.md', icon: '📝' },
  ]);

  const [clipboardHistory, setClipboardHistory] = useState([
    { type: 'url', content: 'https://github.com/some/interesting-repo', time: '1m' },
    { type: 'text', content: 'Some copied text snippet...', time: '5m' },
  ]);

  const getFlexValue = (name) => {
    if (!hoveredComponent) return 1;
    if (hoveredComponent === name) return 2.5;
    return 0.5;
  };

  const GlassPanel = ({ children, name, className = '' }) => (
    <div
      className={`relative overflow-hidden transition-all duration-300 ease-out ${className}`}
      style={{
        flex: getFlexValue(name),
        minHeight: '50px',
        background: 'linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.04) 100%)',
        backdropFilter: 'blur(40px) saturate(180%)',
        borderRadius: '14px',
        border: '1px solid rgba(255,255,255,0.15)',
        boxShadow: '0 8px 32px rgba(0,0,0,0.25), inset 0 1px 0 rgba(255,255,255,0.15)',
        opacity: hoveredComponent && hoveredComponent !== name ? 0.7 : 1,
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

  // Pawkit Extension Component
  const PawkitExtension = () => {
    const isHovered = hoveredComponent === 'pawkit';
    
    return (
      <GlassPanel name="pawkit" className="p-2">
        {/* Header with Pawkit branding */}
        <div className="flex items-center gap-2 mb-2 px-1">
          <span className="text-base">🐾</span>
          <span className="text-[10px] text-white/40 font-medium">PAWKIT</span>
          {inboxItems.length > 0 && (
            <span className="ml-auto text-[9px] bg-orange-500/30 text-orange-300 px-1.5 py-0.5 rounded-full">
              {inboxItems.length} unsorted
            </span>
          )}
        </div>

        {/* Quick search */}
        {isHovered && (
          <div className="mb-2">
            <div className="flex items-center gap-2 bg-white/5 rounded-lg px-2 py-1.5">
              <span className="text-white/40 text-xs">🔍</span>
              <input
                type="text"
                placeholder="Search Pawkit..."
                className="flex-1 bg-transparent text-xs text-white outline-none placeholder:text-white/30"
                value={pawkitSearch}
                onChange={(e) => setPawkitSearch(e.target.value)}
              />
            </div>
          </div>
        )}

        {/* Quick tags */}
        <div className="flex flex-wrap gap-1 mb-2">
          {pawkitTags.slice(0, isHovered ? 5 : 3).map((tag, i) => (
            <button
              key={i}
              className="text-[10px] px-2 py-0.5 rounded-full transition-colors hover:opacity-80"
              style={{ 
                background: `${tag.color}20`, 
                color: tag.color,
                border: `1px solid ${tag.color}40`
              }}
            >
              {tag.name}
              {isHovered && <span className="ml-1 opacity-60">{tag.count}</span>}
            </button>
          ))}
        </div>

        {/* Recent items */}
        <div className="flex-1 overflow-y-auto space-y-1">
          {recentPawkitItems.slice(0, isHovered ? 6 : 2).map((item, i) => (
            <div
              key={i}
              className="flex items-center gap-2 p-1.5 rounded-lg hover:bg-white/10 cursor-pointer transition-colors group"
            >
              <span className="text-sm">
                {item.type === 'bookmark' ? '🔖' : item.type === 'note' ? '📝' : '📄'}
              </span>
              <div className="flex-1 min-w-0">
                <div className="text-[11px] text-white/90 truncate">{item.title}</div>
                {isHovered && item.tags && (
                  <div className="flex gap-1 mt-0.5">
                    {item.tags.slice(0, 2).map((tag, j) => (
                      <span key={j} className="text-[9px] text-white/40">#{tag}</span>
                    ))}
                  </div>
                )}
              </div>
              <span className="text-[9px] text-white/30">{item.time}</span>
            </div>
          ))}
        </div>

        {/* Quick actions */}
        {isHovered && (
          <div className="mt-2 pt-2 border-t border-white/10 flex gap-1">
            <button 
              className="flex-1 text-[10px] text-white/50 hover:text-white/80 py-1.5 rounded hover:bg-white/10 transition-colors"
              onClick={() => {
                setSaveItem({ type: 'note', content: '' });
                setShowSaveModal(true);
              }}
            >
              + Note
            </button>
            <button 
              className="flex-1 text-[10px] text-white/50 hover:text-white/80 py-1.5 rounded hover:bg-white/10 transition-colors"
              onClick={() => {
                setSaveItem({ type: 'bookmark', content: '' });
                setShowSaveModal(true);
              }}
            >
              + Bookmark
            </button>
            <button className="flex-1 text-[10px] text-white/50 hover:text-white/80 py-1.5 rounded hover:bg-white/10 transition-colors">
              Open Pawkit
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  // Enhanced Drop Zone with Pawkit integration
  const DropZoneWithPawkit = () => {
    const [isDragOver, setIsDragOver] = useState(false);
    const isHovered = hoveredComponent === 'dropzone';
    
    return (
      <GlassPanel name="dropzone" className="p-2">
        <div className="flex items-center justify-between mb-2 px-1">
          <span className="text-[10px] text-white/40 font-medium">DROP ZONE</span>
          {stagedFiles.length > 0 && (
            <div className="flex gap-2">
              <button 
                className="text-[10px] text-purple-400/70 hover:text-purple-400 transition-colors flex items-center gap-1"
                onClick={() => {
                  setSaveItem({ type: 'files', files: stagedFiles });
                  setShowSaveModal(true);
                }}
              >
                🐾 Save All
              </button>
              <button 
                className="text-[10px] text-red-400/70 hover:text-red-400 transition-colors"
                onClick={() => setStagedFiles([])}
              >
                Clear
              </button>
            </div>
          )}
        </div>
        <div 
          className={`border border-dashed rounded-lg p-2 flex-1 overflow-y-auto transition-colors ${
            isDragOver ? 'border-purple-400 bg-purple-500/20' : 'border-white/20'
          }`}
          onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
          onDragLeave={() => setIsDragOver(false)}
          onDrop={() => setIsDragOver(false)}
        >
          {stagedFiles.length === 0 ? (
            <div className="text-center text-white/40 text-[10px] py-4">
              <div className="text-2xl mb-2">📥</div>
              <div>Drop files here</div>
              <div className="text-white/30 mt-1">or drag to 🐾 to save to Pawkit</div>
            </div>
          ) : (
            <div className="space-y-1">
              {stagedFiles.map((file, i) => (
                <div 
                  key={i}
                  className="flex items-center gap-2 p-2 bg-white/10 rounded-lg text-xs group cursor-grab hover:bg-white/15 transition-colors"
                  draggable
                >
                  <span className="text-base">{file.icon}</span>
                  <span className="flex-1 truncate text-white/80">{file.name}</span>
                  <button 
                    className="text-purple-400/70 hover:text-purple-400 opacity-0 group-hover:opacity-100 transition-all text-[10px]"
                    onClick={() => {
                      setSaveItem({ type: 'file', file });
                      setShowSaveModal(true);
                    }}
                    title="Save to Pawkit"
                  >
                    🐾
                  </button>
                  <button 
                    className="text-white/30 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all"
                    onClick={() => setStagedFiles(prev => prev.filter((_, idx) => idx !== i))}
                  >
                    ✕
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </GlassPanel>
    );
  };

  // Enhanced Clipboard with Pawkit integration
  const ClipboardWithPawkit = () => {
    const isHovered = hoveredComponent === 'clipboard';
    
    return (
      <GlassPanel name="clipboard" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">CLIPBOARD</div>
        <div className="space-y-1 overflow-y-auto flex-1">
          {clipboardHistory.slice(0, isHovered ? 5 : 2).map((item, i) => (
            <div 
              key={i}
              className={`flex items-center gap-2 p-1.5 rounded-lg cursor-pointer transition-colors group ${
                i === 0 ? 'bg-white/15' : 'hover:bg-white/10'
              }`}
            >
              <span className="text-sm">
                {item.type === 'url' ? '🔗' : item.type === 'image' ? '🖼️' : '📋'}
              </span>
              <span className="text-[11px] text-white/80 flex-1 truncate">{item.content}</span>
              {isHovered && item.type === 'url' && (
                <button 
                  className="text-purple-400/70 hover:text-purple-400 opacity-0 group-hover:opacity-100 transition-all text-[10px]"
                  onClick={() => {
                    setSaveItem({ type: 'bookmark', url: item.content });
                    setShowSaveModal(true);
                  }}
                  title="Bookmark in Pawkit"
                >
                  🐾
                </button>
              )}
              <span className="text-[9px] text-white/30">{item.time}</span>
            </div>
          ))}
        </div>
      </GlassPanel>
    );
  };

  // Save to Pawkit Modal
  const SaveToPawkitModal = () => {
    const [title, setTitle] = useState('');
    const [selectedTags, setSelectedTags] = useState([]);
    const [newTag, setNewTag] = useState('');

    const toggleTag = (tagName) => {
      setSelectedTags(prev => 
        prev.includes(tagName) 
          ? prev.filter(t => t !== tagName)
          : [...prev, tagName]
      );
    };

    return (
      <div 
        className="fixed inset-0 z-50 flex items-center justify-center"
        style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(10px)' }}
        onClick={() => setShowSaveModal(false)}
      >
        <div 
          className="w-[400px] rounded-2xl overflow-hidden"
          style={{
            background: 'linear-gradient(135deg, rgba(40,40,45,0.98) 0%, rgba(25,25,30,0.99) 100%)',
            border: '1px solid rgba(255,255,255,0.1)',
            boxShadow: '0 25px 80px rgba(0,0,0,0.5)',
          }}
          onClick={e => e.stopPropagation()}
        >
          {/* Header */}
          <div className="p-4 border-b border-white/10 flex items-center gap-3">
            <span className="text-2xl">🐾</span>
            <div>
              <h3 className="text-white font-medium">Save to Pawkit</h3>
              <p className="text-[11px] text-white/40">
                {saveItem?.type === 'bookmark' ? 'New bookmark' : 
                 saveItem?.type === 'note' ? 'New note' : 
                 saveItem?.type === 'files' ? `${saveItem.files?.length} files` : 'New item'}
              </p>
            </div>
          </div>

          {/* Content */}
          <div className="p-4 space-y-4">
            {/* Title input */}
            <div>
              <label className="text-[10px] text-white/40 font-medium block mb-1">TITLE</label>
              <input
                type="text"
                placeholder="Enter a title..."
                className="w-full bg-white/5 rounded-lg px-3 py-2 text-sm text-white outline-none border border-white/10 focus:border-purple-500/50 transition-colors"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                autoFocus
              />
            </div>

            {/* URL preview for bookmarks */}
            {saveItem?.type === 'bookmark' && saveItem?.url && (
              <div>
                <label className="text-[10px] text-white/40 font-medium block mb-1">URL</label>
                <div className="bg-white/5 rounded-lg px-3 py-2 text-xs text-white/60 truncate">
                  {saveItem.url}
                </div>
              </div>
            )}

            {/* Files preview */}
            {saveItem?.type === 'files' && (
              <div>
                <label className="text-[10px] text-white/40 font-medium block mb-1">FILES</label>
                <div className="bg-white/5 rounded-lg p-2 space-y-1">
                  {saveItem.files?.map((file, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs text-white/70">
                      <span>{file.icon}</span>
                      <span>{file.name}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Tags */}
            <div>
              <label className="text-[10px] text-white/40 font-medium block mb-2">TAGS</label>
              <div className="flex flex-wrap gap-2 mb-2">
                {pawkitTags.map((tag, i) => (
                  <button
                    key={i}
                    className={`text-[11px] px-2.5 py-1 rounded-full transition-all ${
                      selectedTags.includes(tag.name)
                        ? 'ring-2 ring-offset-1 ring-offset-transparent'
                        : 'opacity-60 hover:opacity-100'
                    }`}
                    style={{ 
                      background: `${tag.color}${selectedTags.includes(tag.name) ? '40' : '20'}`, 
                      color: tag.color,
                      ringColor: tag.color
                    }}
                    onClick={() => toggleTag(tag.name)}
                  >
                    {tag.name}
                  </button>
                ))}
              </div>
              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="+ New tag"
                  className="flex-1 bg-white/5 rounded-lg px-3 py-1.5 text-xs text-white outline-none border border-white/10 focus:border-white/20"
                  value={newTag}
                  onChange={(e) => setNewTag(e.target.value)}
                />
                {newTag && (
                  <button className="text-xs text-purple-400 hover:text-purple-300 px-2">
                    Add
                  </button>
                )}
              </div>
            </div>

            {/* Note content (for notes) */}
            {saveItem?.type === 'note' && (
              <div>
                <label className="text-[10px] text-white/40 font-medium block mb-1">CONTENT</label>
                <textarea
                  placeholder="Write your note..."
                  className="w-full bg-white/5 rounded-lg px-3 py-2 text-sm text-white outline-none border border-white/10 focus:border-purple-500/50 transition-colors resize-none h-24"
                />
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="p-4 border-t border-white/10 flex justify-between items-center">
            <label className="flex items-center gap-2 text-xs text-white/50 cursor-pointer">
              <input type="checkbox" className="rounded" />
              Add to Inbox for later
            </label>
            <div className="flex gap-2">
              <button 
                className="px-4 py-2 text-sm text-white/60 hover:text-white/80 transition-colors"
                onClick={() => setShowSaveModal(false)}
              >
                Cancel
              </button>
              <button 
                className="px-4 py-2 text-sm bg-purple-500/30 text-purple-200 rounded-lg hover:bg-purple-500/40 transition-colors"
                onClick={() => setShowSaveModal(false)}
              >
                Save to Pawkit
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-950 to-slate-900 relative overflow-hidden">
      {/* Background */}
      <div className="absolute top-0 left-1/4 w-[600px] h-[600px] bg-purple-500/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-[500px] h-[500px] bg-blue-500/10 rounded-full blur-3xl" />
      
      {/* Header */}
      <div className="relative z-10 p-4">
        <h1 className="text-white text-lg font-semibold">Sidebar + Pawkit Integration</h1>
        <p className="text-white/50 text-sm">Capture anywhere, organize in Pawkit, find everywhere</p>
      </div>

      {/* Main layout */}
      <div className="flex h-[calc(100vh-80px)] mx-4 rounded-2xl overflow-hidden bg-black/20">
        {/* Sidebar */}
        <div className="w-52 p-2 flex flex-col gap-2">
          {/* Simplified: just showing the Pawkit-relevant components */}
          <GlassPanel name="status" className="p-3">
            <div className="flex items-center justify-between">
              <div className="text-white text-lg font-light">2:45 PM</div>
              <div className="flex gap-2 text-sm">📶 🔋</div>
            </div>
          </GlassPanel>

          <GlassPanel name="apps" className="p-2">
            <div className="text-[10px] text-white/40 font-medium mb-2 px-1">APPS</div>
            <div className="flex gap-2 justify-center">
              {['📁', '🧭', '💻', '⬛', '💬'].map((icon, i) => (
                <div key={i} className="w-8 h-8 rounded-lg bg-white/10 flex items-center justify-center cursor-pointer hover:bg-white/20 transition-colors">
                  {icon}
                </div>
              ))}
            </div>
          </GlassPanel>

          <ClipboardWithPawkit />
          <DropZoneWithPawkit />
          <PawkitExtension />
        </div>

        {/* Desktop content */}
        <div className="flex-1 p-6">
          <div 
            className="rounded-xl overflow-hidden max-w-2xl"
            style={{
              background: 'linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.03) 100%)',
              backdropFilter: 'blur(20px)',
              border: '1px solid rgba(255,255,255,0.1)',
            }}
          >
            <div className="h-10 bg-white/5 flex items-center px-4 border-b border-white/10">
              <div className="flex gap-2">
                <div className="w-3 h-3 rounded-full bg-red-500/70" />
                <div className="w-3 h-3 rounded-full bg-yellow-500/70" />
                <div className="w-3 h-3 rounded-full bg-green-500/70" />
              </div>
              <span className="text-white/60 text-sm ml-4">Sidebar ↔ Pawkit Flow</span>
            </div>
            <div className="p-6 space-y-4">
              <h2 className="text-white text-xl font-light">Capture → Organize → Find</h2>
              
              <div className="space-y-3 text-sm text-white/60">
                <div className="flex items-start gap-3">
                  <span className="text-lg">📋</span>
                  <div>
                    <div className="text-white/80">Copy a URL</div>
                    <div className="text-xs">Clipboard shows 🐾 button to bookmark instantly</div>
                  </div>
                </div>
                
                <div className="flex items-start gap-3">
                  <span className="text-lg">📥</span>
                  <div>
                    <div className="text-white/80">Drop files to staging</div>
                    <div className="text-xs">"Save All to Pawkit" button appears, or save individually</div>
                  </div>
                </div>
                
                <div className="flex items-start gap-3">
                  <span className="text-lg">🐾</span>
                  <div>
                    <div className="text-white/80">Pawkit extension</div>
                    <div className="text-xs">Quick access to recent items, tags, and search</div>
                  </div>
                </div>
                
                <div className="flex items-start gap-3">
                  <span className="text-lg">🔍</span>
                  <div>
                    <div className="text-white/80">⌘K searches everything</div>
                    <div className="text-xs">Apps, files, AND your Pawkit library</div>
                  </div>
                </div>
              </div>

              <div className="pt-4 border-t border-white/10">
                <p className="text-xs text-white/40">
                  Try clicking the 🐾 buttons in the Clipboard or Drop Zone to see the save modal
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Save modal */}
      {showSaveModal && <SaveToPawkitModal />}
    </div>
  );
};

export default PawkitIntegration;
