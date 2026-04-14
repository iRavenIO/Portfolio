import { useEffect, useMemo, useRef, useState } from "react";

export default function AssistantWidgetPage() {
  const [messages, setMessages] = useState([
    { role: "assistant", text: "Hi — ask anything about Kousha, projects, or appointments." },
  ]);
  const [input, setInput] = useState("");
  const [sessionId] = useState(() => cryptoRandomSession());
  const [status, setStatus] = useState("");

  const headers = useMemo(() => ({ "Content-Type": "application/json" }), []);
  const apiBases = useMemo(() => buildApiBases(), []);
  const messagesRef = useRef(null);
  const didInitFromQuery = useRef(false);

  useEffect(() => {
    const el = messagesRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
  }, [messages]);

  const send = async (overrideText) => {
    const text = (overrideText ?? input).trim();
    if (!text) return;

    setInput("");
    setMessages((prev) => [...prev, { role: "user", text }]);
    setStatus("Thinking…");

    try {
      const { data } = await requestWithFallback(apiBases, "/chat", {
        method: "POST",
        headers,
        body: JSON.stringify({ message: text, sessionId }),
      });

      setMessages((prev) => [...prev, { role: "assistant", text: data.reply || "No response." }]);
      setStatus(data?.tier ? `Mode: ${data.tier}` : "");
    } catch (error) {
      const hint = isNetworkError(error)
        ? "Assistant service unavailable. Run: npm run assistant:stack"
        : `Error: ${error.message}`;
      setMessages((prev) => [...prev, { role: "assistant", text: hint }]);
      setStatus("Offline");
    }
  };

  useEffect(() => {
    if (didInitFromQuery.current || typeof window === "undefined") return;
    const params = new URLSearchParams(window.location.search);
    const q = (params.get("q") || "").trim();
    if (!q) return;
    didInitFromQuery.current = true;
    send(q);
  }, []);

  return (
    <main className="assistant-widget-root">
      <section className="assistant-panel" aria-label="Assistant chat panel">
        <header className="assistant-header">
          <h2>Assistant</h2>
          <p>Ask me anything</p>
        </header>

        <div className="assistant-messages" ref={messagesRef}>
          {messages.map((m, i) => (
            <div key={i} className={`assistant-row ${m.role === "user" ? "is-user" : "is-assistant"}`}>
              <div className="assistant-bubble">{m.text}</div>
            </div>
          ))}
        </div>

        <footer className="assistant-footer">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                send();
              }
            }}
            placeholder="Type and press Enter"
            aria-label="Message input"
          />
          <div className="assistant-status">{status}</div>
        </footer>
      </section>

      <style jsx global>{`
        .assistant-widget-root {
          width: 100%;
          height: 100%;
          overflow: hidden;
          box-sizing: border-box;
          font-family: inherit;
          color: #f2f2f2;
          background: transparent;
          padding: 0;
          min-width: 0;
        }

        .assistant-panel {
          height: 100%;
          width: 100%;
          max-width: 100%;
          display: flex;
          flex-direction: column;
          overflow: hidden;
          border-radius: 14px;
          border: 1px solid rgba(214, 214, 214, 0.16);
          background: rgba(9, 9, 12, 0.56);
          box-shadow: 0 14px 30px rgba(0, 0, 0, 0.34);
          backdrop-filter: blur(8px);
          -webkit-backdrop-filter: blur(8px);
          contain: layout paint;
        }

        .assistant-header {
          flex: 0 0 auto;
          padding: 0.72rem 0.82rem 0.56rem;
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }

        .assistant-header h2 {
          margin: 0;
          font-size: 0.9rem;
          font-weight: 600;
          letter-spacing: 0.01em;
        }

        .assistant-header p {
          margin: 0.15rem 0 0;
          font-size: 0.75rem;
          opacity: 0.62;
        }

        .assistant-messages {
          flex: 1 1 auto;
          min-height: 0;
          overflow-y: auto;
          overflow-x: hidden;
          overscroll-behavior: contain;
          padding: 0.72rem 0.72rem 0.58rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          scrollbar-width: thin;
          scrollbar-color: rgba(255, 255, 255, 0.2) transparent;
        }

        .assistant-messages::-webkit-scrollbar {
          width: 8px;
        }

        .assistant-messages::-webkit-scrollbar-thumb {
          background: rgba(255, 255, 255, 0.2);
          border-radius: 999px;
        }

        .assistant-row {
          display: flex;
          width: 100%;
        }

        .assistant-row.is-assistant {
          justify-content: flex-start;
        }

        .assistant-row.is-user {
          justify-content: flex-end;
        }

        .assistant-bubble {
          max-width: 84%;
          padding: 0.56rem 0.68rem;
          border-radius: 10px;
          line-height: 1.38;
          font-size: 0.86rem;
          white-space: pre-wrap;
          word-break: break-word;
          overflow-wrap: anywhere;
        }

        .assistant-row.is-assistant .assistant-bubble {
          background: rgba(255, 255, 255, 0.09);
          border: 1px solid rgba(255, 255, 255, 0.08);
        }

        .assistant-row.is-user .assistant-bubble {
          background: rgba(255, 255, 255, 0.16);
          border: 1px solid rgba(255, 255, 255, 0.14);
        }

        .assistant-footer {
          flex: 0 0 auto;
          padding: 0.54rem 0.65rem 0.62rem;
          border-top: 1px solid rgba(255, 255, 255, 0.08);
          background: rgba(8, 8, 10, 0.56);
          backdrop-filter: blur(6px);
          -webkit-backdrop-filter: blur(6px);
        }

        .assistant-footer input {
          width: 100%;
          box-sizing: border-box;
          border: 1px solid rgba(255, 255, 255, 0.14);
          border-radius: 8px;
          padding: 0.58rem 0.62rem;
          color: #f2f2f2;
          background: rgba(0, 0, 0, 0.2);
          outline: none;
          font: inherit;
          font-size: 0.85rem;
        }

        .assistant-footer input::placeholder {
          color: rgba(242, 242, 242, 0.55);
        }

        .assistant-status {
          margin-top: 0.3rem;
          min-height: 1em;
          font-size: 0.72rem;
          opacity: 0.58;
        }

        @media (max-width: 980px) {
          .assistant-panel {
            border-radius: 12px;
          }
          .assistant-header,
          .assistant-footer {
            padding-left: 0.65rem;
            padding-right: 0.65rem;
          }
          .assistant-messages {
            padding-left: 0.65rem;
            padding-right: 0.65rem;
          }
          .assistant-bubble {
            max-width: 92%;
          }
        }
      `}</style>
    </main>
  );
}

function cryptoRandomSession() {
  try {
    if (typeof crypto !== "undefined" && crypto.randomUUID) return crypto.randomUUID();
  } catch {
    // no-op
  }
  return `session-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function buildApiBases() {
  const configured = process.env.NEXT_PUBLIC_ASSISTANT_API_BASE;
  const bases = [];
  if (configured) bases.push(configured);

  if (typeof window !== "undefined") {
    bases.push(`${window.location.protocol}//${window.location.hostname}:8787/v1`);
  }

  bases.push("/assistant-api/v1");
  return [...new Set(bases)].filter(Boolean);
}

async function requestWithFallback(apiBases, endpoint, init) {
  let lastError = null;
  for (const base of apiBases) {
    try {
      const res = await fetch(`${base}${endpoint}`, init);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `Request failed (${res.status})`);
      return { data, base };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("NetworkError when attempting to fetch resource.");
}

function isNetworkError(error) {
  const message = String(error?.message || "").toLowerCase();
  return (
    message.includes("networkerror") ||
    message.includes("failed to fetch") ||
    message.includes("load failed") ||
    message.includes("fetch")
  );
}
