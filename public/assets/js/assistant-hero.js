(() => {
  const SESSION_KEY = "kousha_assistant_session_id";

  const hero = document.querySelector("[data-assistant-hero]");
  if (!hero) return;

  const form = hero.querySelector(".assistant-hero__form");
  const input = form?.querySelector("input[name='q']");
  const layer = hero.querySelector(".assistant-float-layer");
  if (!form || !input || !layer) return;

  form.addEventListener("submit", onSubmit);
  input.addEventListener("focus", refreshPromptState);
  input.addEventListener("blur", refreshPromptState);
  input.addEventListener("input", refreshPromptState);

  function refreshPromptState() {
    const isActive = document.activeElement === input || input.value.trim().length > 0;
    hero.classList.toggle("is-active", isActive);
  }

  function getSessionId() {
    const existing = sessionStorage.getItem(SESSION_KEY);
    if (existing) return existing;

    const next =
      typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `sess-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

    sessionStorage.setItem(SESSION_KEY, next);
    return next;
  }

  function buildApiBases() {
    const configured = (hero.dataset.apiBase || "").trim();
    const bases = [];

    if (configured) bases.push(configured);
    if (typeof window !== "undefined") {
      bases.push(`${window.location.protocol}//${window.location.hostname}:8787/v1`);
    }
    bases.push("/assistant-api/v1");

    return [...new Set(bases)].filter(Boolean);
  }

  async function sendToHermesBackend(message, sessionId) {
    const payload = { message, sessionId };
    const bases = buildApiBases();
    let lastError = null;

    for (const base of bases) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 12_000);

      try {
        const response = await fetch(`${base}/chat`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
          signal: controller.signal,
        });

        const data = await response.json().catch(() => ({}));
        if (!response.ok) {
          throw new Error(data?.error || `Request failed (${response.status})`);
        }

        return data;
      } catch (error) {
        lastError = error;
      } finally {
        clearTimeout(timeout);
      }
    }

    throw lastError || new Error("NetworkError when attempting to fetch resource.");
  }

  function extractAssistantReply(data) {
    if (typeof data?.reply === "string" && data.reply.trim()) return sanitizeReply(data.reply);
    if (typeof data?.result?.message === "string" && data.result.message.trim()) {
      return sanitizeReply(data.result.message);
    }
    return "I am here.";
  }

  function sanitizeReply(value) {
    const raw = String(value || "").trim();
    if (!raw) return "I am here.";

    const metadataLike =
      /kousha\s+madani\s+[-—]?\s*cv\s*summary/i.test(raw) ||
      /assistant-readable\s+cv\s+context/i.test(raw) ||
      /public\s+context\s+usage/i.test(raw);

    if (metadataLike) {
      return "Hey — happy to help. Ask me about Kousha’s background, projects, or how to get in touch.";
    }

    return raw
      .replace(/```[\s\S]*?```/g, " ")
      .replace(/^#{1,6}\s+/gm, "")
      .replace(/\*\*/g, "")
      .replace(/\s+/g, " ")
      .trim();
  }

  function addFloatingMessage(text, role) {
    const activeCount = layer.querySelectorAll(".assistant-float-message").length;
    const startOffset = Math.min(activeCount * 18, 140);
    const message = document.createElement("p");
    message.className = `assistant-float-message is-${role}`;
    message.textContent = text;
    message.style.setProperty("--start", `${startOffset}px`);
    message.style.setProperty("--drift", `${(Math.random() * 18 - 9).toFixed(2)}px`);
    message.style.setProperty("--rise", `${(64 + Math.random() * 18).toFixed(2)}vh`);
    message.style.setProperty("--dur", `${(5.6 + Math.random() * 1.9).toFixed(2)}s`);
    layer.appendChild(message);

    requestAnimationFrame(() => {
      message.classList.add("is-visible");
    });

    message.addEventListener(
      "animationend",
      () => {
        message.remove();
      },
      { once: true }
    );
  }

  async function onSubmit(event) {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;

    addFloatingMessage(text, "user");
    input.value = "";
    refreshPromptState();

    try {
      const sessionId = getSessionId();
      const data = await sendToHermesBackend(text, sessionId);
      addFloatingMessage(extractAssistantReply(data), "assistant");
    } catch (error) {
      const message =
        String(error?.message || "").toLowerCase().includes("fetch") ||
        String(error?.message || "").toLowerCase().includes("network")
          ? "Assistant is unavailable right now."
          : `Assistant error: ${error.message}`;

      addFloatingMessage(message, "assistant");
    }
  }
})();
