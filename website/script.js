const canvas = document.querySelector("#cider-river");
const ctx = canvas.getContext("2d");
const reveals = document.querySelectorAll(".reveal");

let width = 0;
let height = 0;
let time = 0;
let scrollProgress = 0;

const particles = Array.from({ length: 76 }, (_, index) => ({
  offset: Math.random(),
  speed: 0.00018 + Math.random() * 0.00036,
  side: Math.random() > 0.5 ? 1 : -1,
  size: 1 + Math.random() * 2.8,
  index
}));

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  width = window.innerWidth;
  height = window.innerHeight;
  canvas.width = width * dpr;
  canvas.height = height * dpr;
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function updateScroll() {
  const max = document.documentElement.scrollHeight - height;
  scrollProgress = max > 0 ? window.scrollY / max : 0;
}

function easeInOut(t) {
  const clamped = Math.max(0, Math.min(1, t));
  return clamped * clamped * (3 - 2 * clamped);
}

function riverPoint(t, pullBack = 1) {
  const cinematic = easeInOut(scrollProgress * 1.12) * 0.72;
  const centerX =
    width * (0.58 + Math.sin(t * 8.6 + cinematic * 3.8) * (0.08 + cinematic * 0.17));
  const centerY = height * (1.08 - t * (1.42 - cinematic * 0.2));
  const perspective = 1 + (1 - t) * (2.6 - cinematic * 1.65);
  const wobble = Math.sin(t * 26 + time * 0.025) * 18 * cinematic;

  return {
    x: centerX + wobble * pullBack,
    y: centerY,
    perspective
  };
}

function drawRiver() {
  ctx.clearRect(0, 0, width, height);

  const closeRide = 1 - easeInOut(scrollProgress * 0.55) * 0.18;
  const streamWidth = 276 + closeRide * 18;
  const leftBank = [];
  const rightBank = [];
  const centerLine = [];

  for (let i = 0; i <= 132; i += 1) {
    const t = i / 132;
    const point = riverPoint(t, 1);
    const pulse = Math.sin(t * 21 + time * 0.018) * 0.06 + Math.sin(t * 45 - time * 0.012) * 0.035;
    const bankWidth = (streamWidth * (0.62 + pulse)) / point.perspective;
    const tangent = Math.cos(t * 9 + easeInOut(scrollProgress) * 3.2) * 0.55;
    const angle = Math.atan(tangent);
    const normalX = Math.cos(angle);

    centerLine.push({ x: point.x, y: point.y, width: bankWidth, perspective: point.perspective, t });
    leftBank.push({ x: point.x - bankWidth * normalX, y: point.y });
    rightBank.push({ x: point.x + bankWidth * normalX, y: point.y });
  }

  const bounds = {
    minX: Math.min(...leftBank.map(p => p.x)),
    maxX: Math.max(...rightBank.map(p => p.x))
  };

  const riverGradient = ctx.createLinearGradient(bounds.minX, 0, bounds.maxX, 0);
  riverGradient.addColorStop(0, "rgba(82, 31, 5, 0.62)");
  riverGradient.addColorStop(0.16, "rgba(165, 76, 8, 0.74)");
  riverGradient.addColorStop(0.38, "rgba(244, 164, 43, 0.96)");
  riverGradient.addColorStop(0.58, "rgba(255, 185, 67, 0.92)");
  riverGradient.addColorStop(0.78, "rgba(217, 119, 6, 0.8)");
  riverGradient.addColorStop(1, "rgba(64, 25, 6, 0.58)");

  ctx.save();
  ctx.shadowBlur = 34 + closeRide * 18;
  ctx.shadowColor = "rgba(244, 164, 43, 0.42)";
  ctx.beginPath();
  leftBank.forEach((point, index) => {
    if (index === 0) ctx.moveTo(point.x, point.y);
    else ctx.lineTo(point.x, point.y);
  });
  rightBank.slice().reverse().forEach(point => ctx.lineTo(point.x, point.y));
  ctx.closePath();
  ctx.fillStyle = riverGradient;
  ctx.fill();
  ctx.restore();

  ctx.save();
  ctx.globalCompositeOperation = "screen";
  for (let band = 0; band < 5; band += 1) {
    ctx.beginPath();
    centerLine.forEach((point, index) => {
      const drift = Math.sin(point.t * (18 + band * 4) + time * (0.018 + band * 0.002)) * point.width * 0.16;
      const x = point.x + drift + (band - 2) * point.width * 0.1;
      if (index === 0) ctx.moveTo(x, point.y);
      else ctx.lineTo(x, point.y);
    });
    const highlight = ctx.createLinearGradient(bounds.minX, 0, bounds.maxX, 0);
    highlight.addColorStop(0, "rgba(255, 226, 146, 0)");
    highlight.addColorStop(0.5, `rgba(255, 219, 118, ${0.08 + band * 0.012})`);
    highlight.addColorStop(1, "rgba(255, 226, 146, 0)");
    ctx.strokeStyle = highlight;
    ctx.lineWidth = Math.max(6, streamWidth * (0.055 - band * 0.005));
    ctx.lineCap = "round";
    ctx.stroke();
  }
  ctx.restore();

  ctx.save();
  ctx.globalCompositeOperation = "multiply";
  ctx.globalAlpha = 0.28;
  for (const side of [-1, 1]) {
    ctx.beginPath();
    centerLine.forEach((point, index) => {
      const x = point.x + side * point.width * (0.72 + Math.sin(point.t * 31 + time * 0.012) * 0.06);
      if (index === 0) ctx.moveTo(x, point.y);
      else ctx.lineTo(x, point.y);
    });
    ctx.strokeStyle = "rgba(64, 23, 4, 0.78)";
    ctx.lineWidth = 38 + closeRide * 28;
    ctx.lineCap = "round";
    ctx.stroke();
  }
  ctx.restore();

  for (const particle of particles) {
    particle.offset = (particle.offset + particle.speed) % 1;
    const point = riverPoint(particle.offset, 1);
    const wave = Math.sin(time * 0.022 + particle.index + particle.offset * 40);
    const spread = (streamWidth * 0.42) / point.perspective;
    const x = point.x + particle.side * spread * (0.25 + Math.abs(wave));
    const y = point.y + wave * 13;
    const alpha = Math.max(0, 1 - Math.abs(y - height * 0.5) / height);

    ctx.beginPath();
    ctx.fillStyle = `rgba(255, ${160 + Math.floor(wave * 30)}, 62, ${0.12 + alpha * 0.46})`;
    ctx.arc(x, y, particle.size / point.perspective + closeRide * 0.8, 0, Math.PI * 2);
    ctx.fill();
  }

}

function animate() {
  time += 1;
  drawRiver();
  requestAnimationFrame(animate);
}

const revealObserver = new IntersectionObserver(
  entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) entry.target.classList.add("is-visible");
    }
  },
  { threshold: 0.18 }
);

for (const reveal of reveals) revealObserver.observe(reveal);

for (const reveal of reveals) {
  const rect = reveal.getBoundingClientRect();
  if (rect.top < window.innerHeight * 0.9) {
    reveal.classList.add("is-visible");
  }
}

window.addEventListener("resize", () => {
  resize();
  updateScroll();
});

window.addEventListener("scroll", updateScroll, { passive: true });

resize();
updateScroll();
animate();
