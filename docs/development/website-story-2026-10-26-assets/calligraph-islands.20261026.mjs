import React, { useEffect, useMemo, useState } from "https://esm.sh/react@19.1.0";
import { createRoot } from "https://esm.sh/react-dom@19.1.0/client";
import { Calligraph } from "https://esm.sh/calligraph@1.4.1?deps=react@19.1.0,react-dom@19.1.0";

const e = React.createElement;
const prefersReducedMotion =
  window.matchMedia &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const DESKTOP_QUERY = "(min-width: 820px)";
const NUMBER_REVEAL_DELAY_MS = 180;
const TEXT_REVEAL_DELAY_MS = 900;

window.__ifcCalligraphReady = true;

function currentLang() {
  return document.documentElement.lang &&
    document.documentElement.lang.toLowerCase().startsWith("en")
    ? "en"
    : "zh";
}

function getStartValue(host) {
  const lang = currentLang();
  return (
    host.getAttribute(`data-calligraph-from-${lang}`) ||
    host.getAttribute("data-calligraph-from") ||
    host.textContent ||
    ""
  );
}

function hasStartValue(host) {
  return Boolean(
    host.hasAttribute("data-calligraph-from") ||
      host.hasAttribute("data-calligraph-from-zh") ||
      host.hasAttribute("data-calligraph-from-en"),
  );
}

function revealDelayForHost(host) {
  return host.getAttribute("data-calligraph-variant") === "text"
    ? TEXT_REVEAL_DELAY_MS
    : NUMBER_REVEAL_DELAY_MS;
}

function revealTriggerForHost(host) {
  return host.getAttribute("data-calligraph-variant") === "text"
    ? host
    : host.closest("[data-calligraph-trigger]") || host;
}

function observerOptions() {
  const isDesktop = window.matchMedia && window.matchMedia(DESKTOP_QUERY).matches;
  return isDesktop
    ? { threshold: 0.58, rootMargin: "0px 0px -8% 0px" }
    : { threshold: 0.32, rootMargin: "0px 0px -12% 0px" };
}

function useRevealActive(host) {
  const [active, setActive] = useState(() => !hasStartValue(host));

  useEffect(() => {
    if (prefersReducedMotion || !("IntersectionObserver" in window)) {
      setActive(true);
      return;
    }

    const trigger = revealTriggerForHost(host);
    const revealDelay = revealDelayForHost(host);
    let revealTimer = null;
    let observer = null;

    function activate() {
      window.clearTimeout(revealTimer);
      revealTimer = window.setTimeout(() => {
        setActive(true);
        revealTimer = null;
      }, revealDelay);
    }

    function deactivate() {
      window.clearTimeout(revealTimer);
      revealTimer = null;
      setActive(false);
    }

    function connect() {
      if (observer) observer.disconnect();
      observer = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (entry.isIntersecting) {
              activate();
            } else {
              deactivate();
            }
          }
        },
        observerOptions(),
      );
      observer.observe(trigger);
    }

    connect();
    const onResize = () => connect();
    window.addEventListener("resize", onResize, { passive: true });

    return () => {
      window.clearTimeout(revealTimer);
      window.removeEventListener("resize", onResize);
      if (observer) observer.disconnect();
    };
  }, [host]);

  return active;
}

function CalligraphIsland({ host }) {
  const [startValue, setStartValue] = useState(() => getStartValue(host));
  const [target, setTarget] = useState(
    () => host.getAttribute("data-calligraph-target") || host.textContent || "",
  );
  const active = useRevealActive(host);

  useEffect(() => {
    const observer = new MutationObserver(() => {
      setStartValue(getStartValue(host));
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["lang"],
    });

    return () => observer.disconnect();
  }, [host]);

  useEffect(() => {
    const observer = new MutationObserver(() => {
      setTarget(host.getAttribute("data-calligraph-target") || "");
    });

    observer.observe(host, {
      attributes: true,
      attributeFilter: ["data-calligraph-target"],
    });

    return () => observer.disconnect();
  }, [host]);

  useEffect(() => {
    host.setAttribute("aria-label", target);
  }, [host, target]);

  const variant = host.getAttribute("data-calligraph-variant") || "number";
  const displayText = useMemo(() => {
    return active ? target : startValue;
  }, [active, startValue, target]);
  const isTextVariant = variant === "text";

  // Keep the existing glyph morph, drift and reveal timing. Group text into
  // readable units so animated inline boxes cannot split an English word or
  // strand Chinese punctuation on its own line.
  if (prefersReducedMotion) return e("span", { style: { whiteSpace: "normal" } }, target);

  const options = {
    as: "span",
    variant,
    initial: false,
    autoSize: !isTextVariant,
    animation: "smooth",
    drift: { x: 18, y: 8 },
    trend: 1,
    stagger: 0.045,
    style: { display: "inline-flex", alignItems: "baseline", whiteSpace: "pre", flexWrap: "nowrap" },
  };
  if (!isTextVariant) return e(Calligraph, options, displayText);

  const parts = currentLang() === "zh"
    ? displayText.match(/[^，。！？\n]+[，。！？]?/g) || [displayText]
    : displayText.match(/\S+\s*/g) || [displayText];
  return e("span", { "aria-hidden": true, style: { display: "inline" } },
    ...parts.flatMap((part, index) => [
      e(Calligraph, { ...options, key: `part-${index}`, autoSize: false }, part),
      e("wbr", { key: `break-${index}` }),
    ]),
  );
}

for (const host of document.querySelectorAll("[data-calligraph]")) {
  host.textContent = "";
  host.setAttribute("role", "text");
  createRoot(host).render(e(CalligraphIsland, { host }));
}
