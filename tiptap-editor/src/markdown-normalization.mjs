const taskListItemSpacingPattern = /^(\s*(?:[-+*]|\d+[.)])\s+\[(?: |x|X)\])([ \t]+)(.*)$/;
const markdownFencePattern = /^(\s*)(`{3,}|~{3,})/;
const brokenTaskMarkerPattern = /^(\s*(?:[-+*]|\d+[.)])\s+)\\?\[( |x|X)\\?\]\s*$/;
const listMarkerPattern = /^(?:[-+*]|\d+[.)])\s+/;
const indentedContinuationPattern = /^\s{2,}\S.*$/;
const paragraphLinePattern = /^<p(?:\s+style="[^"]*")?\s*>(.*?)<\/p>$/i;
const emptyParagraphLinePattern = /^<p(?:\s+style="[^"]*")?\s*><\/p>$/i;
const inlineTaskParagraphPattern = /^(\s*(?:[-+*]|\d+[.)])\s+\[(?: |x|X)\])\s*<p(?:\s+style="[^"]*")?\s*>(.*?)<\/p>\s*$/i;

function decodeBasicHtmlEntities(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return '';
  }

  return value
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');
}

function stripHtmlTags(value) {
  return String(value ?? '').replace(/<[^>]*>/g, '');
}

function normalizeFenceState(activeFence, line) {
  const fenceMatch = line.match(markdownFencePattern);
  if (!fenceMatch) return activeFence;

  const marker = fenceMatch[2][0];
  const markerLength = fenceMatch[2].length;

  if (!activeFence) {
    return { marker, markerLength };
  }

  if (activeFence.marker === marker && markerLength >= activeFence.markerLength) {
    return null;
  }

  return activeFence;
}

function extractParagraphText(line, decodeEntities) {
  const trimmed = line.trim();
  const match = trimmed.match(paragraphLinePattern);
  if (!match) return null;
  return decodeEntities(stripHtmlTags(match[1])).trim();
}

function extractIndentedContinuationText(line, decodeEntities) {
  if (!indentedContinuationPattern.test(line)) {
    return null;
  }

  const trimmed = line.trim();
  if (
    trimmed.length === 0
    || listMarkerPattern.test(trimmed)
    || trimmed.startsWith('<')
    || trimmed.startsWith('>')
    || trimmed.startsWith('#')
    || trimmed.startsWith('|')
    || trimmed.startsWith('```')
    || trimmed.startsWith('~~~')
  ) {
    return null;
  }

  return decodeEntities(stripHtmlTags(trimmed)).trim();
}

function repairBrokenTaskItems(markdown, options = {}) {
  if (typeof markdown !== 'string' || markdown.length === 0) {
    return '';
  }

  const decodeEntities = options.decodeEntities ?? decodeBasicHtmlEntities;
  const lines = markdown.split('\n');
  const repaired = [];
  let activeFence = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    activeFence = normalizeFenceState(activeFence, line);

    if (activeFence) {
      repaired.push(line);
      continue;
    }

    const inlineTaskParagraphMatch = line.match(inlineTaskParagraphPattern);
    if (inlineTaskParagraphMatch) {
      const [, marker, rawText] = inlineTaskParagraphMatch;
      const text = decodeEntities(stripHtmlTags(rawText)).trim();
      repaired.push(text.length === 0 ? marker : `${marker} ${text}`);
      continue;
    }

    const markerMatch = line.match(brokenTaskMarkerPattern);
    if (!markerMatch) {
      repaired.push(line);
      continue;
    }

    const [, markerPrefix, check] = markerMatch;
    let nextIndex = index + 1;

    while (nextIndex < lines.length && lines[nextIndex].trim() === '') {
      nextIndex += 1;
    }

    const paragraphText = nextIndex < lines.length
      ? extractParagraphText(lines[nextIndex], decodeEntities)
      : null;

    const continuationText = paragraphText ?? (
      nextIndex < lines.length
        ? extractIndentedContinuationText(lines[nextIndex], decodeEntities)
        : null
    );

    if (continuationText === null) {
      repaired.push(`${markerPrefix}[${check}]`);
      continue;
    }

    const marker = `${markerPrefix}[${check}]`;
    repaired.push(continuationText.length === 0 ? marker : `${marker} ${continuationText}`);
    nextIndex += 1;

    while (nextIndex < lines.length) {
      const trimmed = lines[nextIndex].trim();
      if (trimmed === '' || emptyParagraphLinePattern.test(trimmed)) {
        nextIndex += 1;
        continue;
      }
      break;
    }

    index = nextIndex - 1;
  }

  return repaired.join('\n');
}

function normalizeTaskListSpacing(markdown) {
  if (typeof markdown !== 'string' || markdown.length === 0) {
    return '';
  }

  const lines = markdown.split('\n');
  let activeFence = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    activeFence = normalizeFenceState(activeFence, line);
    if (line.match(markdownFencePattern)) continue;

    if (activeFence) continue;

    const taskLineMatch = line.match(taskListItemSpacingPattern);
    if (!taskLineMatch) continue;

    const [, marker, , content] = taskLineMatch;
    lines[index] = content.length === 0 ? marker : `${marker} ${content}`;
  }

  return lines.join('\n');
}

function normalizeMarkdownForPersistence(markdown, options = {}) {
  const repaired = repairBrokenTaskItems(markdown, options);
  return normalizeTaskListSpacing(repaired);
}

export {
  normalizeMarkdownForPersistence,
  normalizeTaskListSpacing,
  repairBrokenTaskItems,
};
