Cider
AI Strategy & Architecture
Internal Product Document  ·  March 2026

Overview
Cider's AI strategy is built around a simple principle: give users the right level of AI for their comfort and needs, without forcing anyone into a subscription or cloud dependency. Every AI feature in Cider is opt-in, privacy-respecting, and additive — users can go deeper as they want, or ignore AI entirely.
This document captures the three-tier AI model, local model recommendations, fine-tuning strategy, and the competitive moat that open file formats create.

The Three-Tier AI Model
Cider supports three distinct AI tiers. Each tier serves a different type of user and requires zero compromise from the others.

Tier 1 — Apple Intelligence
Zero setup · Always available · Limited capability
Apple Intelligence is available to all users immediately with no configuration. It handles basic tasks like simple summarization, autocomplete, and light text processing. It's not powerful enough for smart tagging or meaningful content analysis, but it's a solid baseline for users who just want things to work.
Best for: Non-technical users who want basic AI assistance without any setup.

Tier 2 — Local Bundled Model
Opt-in download · ~1–2GB · On-device · No subscription
Users can opt in to download a small, capable language model that runs entirely on their Mac. Once downloaded, this unlocks real AI features inside Cider:
	•	Auto-tagging saved bookmarks and notes
	•	Summarizing long-form content on save
	•	In-app chat to ask questions about your vault
	•	Semantic search across saved content
	•	Smart sorting and filtering of captures
Everything runs on-device. No data leaves the machine. This is the privacy-first power tier for users who want real AI without any cloud dependency or ongoing cost.
Best for: Privacy-conscious users and people who want strong AI features without a subscription.

Tier 3 — CLI Power Users
No setup required · Bring your own LLM · Unlimited capability
Power users can skip the in-app AI entirely and interact with their Cider vault directly through the terminal using any LLM they choose — Claude, Gemini, Codex, or any other CLI-accessible model.
This works out of the box because Cider stores everything as real files on disk:
	•	Bookmarks → .webloc files
	•	Notes → .md files
	•	Images → .jpeg / .png
	•	Folders in the sidebar → actual folders in Finder
Any AI that can read files can work with a Cider vault. Users can tell their LLM to organize bookmarks, summarize notes, tag captures, or restructure their entire vault — and every change reflects instantly in Cider.
Best for: Developers, researchers, and power users who are already using AI tooling in the terminal.

Local Model Recommendations
For Tier 2, Cider needs a model that is small enough to be a reasonable download, fast enough to feel snappy on Apple Silicon, capable enough to handle summarization and tagging well, and permissively licensed for commercial bundling.

Recommended: Phi-4 Mini (Microsoft)
Phi-4 Mini is the current top recommendation for bundling with Cider. It punches significantly above its weight on structured tasks like classification, tagging, and summarization. Microsoft's license is permissive for commercial use, and it runs fast on Apple Silicon via MLX.
	•	Size: ~2GB
	•	License: MIT
	•	Strengths: Structured tasks, summarization, classification
	•	Runtime: MLX (Apple Silicon optimized)

Alternative: Qwen3 4B (Alibaba)
Qwen3 is a strong alternative with good multilingual support and solid reasoning for its size. Already proven on-device on iPhone 15 Pro Max, so Apple Silicon Macs will handle it easily. Good for summarization and chat.
	•	Size: ~2.3GB
	•	License: Apache 2.0 (commercial friendly)
	•	Strengths: Chat, multilingual, reasoning
	•	Runtime: llama.cpp or MLX

Alternative: Gemma 3 4B (Google)
Google's Gemma 3 is well-rounded and benefits from strong instruction-following. Apache 2.0 licensed, solid all-rounder for Cider's use cases.
	•	Size: ~2.5GB
	•	License: Gemma Terms of Use (commercial friendly)
	•	Strengths: Instruction following, general tasks

Runtime: MLX vs Ollama
For bundling with Cider, MLX is the recommended runtime. It's Apple's own framework, optimized specifically for Apple Silicon, and consistently faster than llama.cpp on M-series chips. It's also the most native-feeling integration for a macOS app.
Ollama is a viable alternative for users who already have it installed — Cider could detect an active Ollama instance and use it as a free upgrade path, falling back gracefully to the bundled model or Apple Intelligence if not present.

Training the Model for Cider
Full fine-tuning a model for Cider is overkill — the tasks are focused and well-defined enough that tight system prompts and few-shot examples get 90% of the way there. The strategy is prompt engineering first, fine-tuning only if needed.

Prompting Strategy by Task
Auto-Tagging
Provide the model with Cider's tag taxonomy as context, then ask it to classify. A system prompt like 'You are a personal knowledge management assistant. Given the following content, suggest 2-5 tags from this list: [tags]. Return only the tags as a comma-separated list.' works reliably with Phi-4 Mini and Qwen3.
Summarization
Few-shot examples work well here. Show the model 2-3 examples of a bookmark URL + page content + ideal Cider-style summary (1-2 sentences, no fluff). The model quickly learns the desired tone and length.
Smart Sorting
Ask the model to return structured JSON with a category, priority score, and suggested folder. Structured output prompting (asking for JSON explicitly) is well-supported by all recommended models.
In-App Chat
System prompt establishes the vault context: 'You are an assistant helping the user manage their personal knowledge vault. The vault contains the following items: [list]. Answer questions about their saved content and help them organize it.' Pass relevant file contents as context per query.

When Fine-Tuning Makes Sense
Fine-tuning becomes worth exploring if Cider develops a sufficiently large user base and collects (with consent) examples of good tagging and sorting decisions. A LoRA fine-tune on Phi-4 Mini with ~1,000 Cider-specific examples would likely produce noticeably better results for tagging and categorization than prompt engineering alone. This is a v2+ consideration.

The Competitive Moat: Open Files
Cider's most defensible advantage isn't the UI or the AI features — it's the file format philosophy. Everything in Cider is a real file in a real folder on the user's Mac. This creates a moat that locked-garden competitors cannot replicate without rebuilding from scratch.

Why This Matters
Most PKM tools trap user data in proprietary formats or cloud databases. Leaving Notion means export pain. Leaving Roam means wrestling with JSON. Leaving Craft means losing formatting. Cider users never face this problem — their vault is just a folder. They could delete Cider tomorrow and lose nothing.
Paradoxically, this is what makes users trust Cider enough to commit to it.

The AI Amplifier
Open file formats don't just create trust — they create a compounding AI advantage. Because the vault is plain files, any AI can interact with it without special integration:
	•	Claude Code agents can read and reorganize the vault
	•	Power users can prompt any LLM to restructure their notes
	•	Future AI tools Cider hasn't built yet will work automatically
	•	The vault is indexable, searchable, and portable across any tool
No competitor offering a closed format can claim this. A user's Cider vault gets more useful as AI tooling improves industrywide, with zero effort from the Cider team.

The Marketing Angle
This story is simple and resonant across all three user tiers:
	•	To the non-technical user: "Your data is yours. Always."
	•	To the privacy-conscious user: "Nothing leaves your Mac. Ever."
	•	To the power user: "Your vault is a folder. Your AI already knows how to use it."
One product, three clear value propositions, zero overlap. This is the kind of positioning that earns word-of-mouth in developer and privacy communities — exactly the audiences most likely to become Cider's early evangelists.

Summary
Cider's AI architecture is a tiered opt-in system that serves every type of user without compromise. The open file format philosophy is both the technical foundation and the competitive moat. Local AI — specifically MLX + Phi-4 Mini or Qwen3 — gives users real capability without cloud dependency. And power users don't need any of it, because their LLM already speaks the language of files.
The strategy is: start with what Apple gives you for free, go deeper when users want it, and never lock anyone in.

