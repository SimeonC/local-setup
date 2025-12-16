// ==UserScript==
// @name        Google Meets
// @namespace   Local Scripts
// @match       https://meet.google.com/*
// @grant       none
// @version     1.0
// @author      -
// @description 9/10/2025, 3:07:34 PM
// ==/UserScript==

const joinKey = "ctrl-alt-meta-shift-j";

const modifiers = ["ctrl", "alt", "meta", "shift"];

const joinKeyParts = joinKey.split("-");

function testEventSequence(event, sequence) {
  for (const command of sequence) {
    switch (command) {
      case "ctrl": {
        if (!event.ctrlKey) return false;
        break;
      }
      case "alt": {
        if (!event.altKey) return false;
        break;
      }
      case "meta": {
        if (!event.metaKey) return false;
        break;
      }
      case "shift": {
        if (!event.shiftKey) return false;
        break;
      }
      default: {
        if (`key${command}` !== event.code.toLowerCase() && command !== event.key.toLowerCase())
          return false;
      }
    }
  }
  return true;
}

function testEvent(event) {
  if (testEventSequence(event, joinKeyParts)) return "join";
  return false;
}

window.addEventListener("keydown", (event) => {
  const commandType = testEvent(event);
  if (commandType === "join") {
    document
      .evaluate("//button[contains(., 'Join now')]", document, null, XPathResult.ANY_TYPE, null)
      .iterateNext()
      .click();
  }
});

// ===== start meeting extension

(function () {
  const ENDPOINT = "https://localhost:1234";
  const HEARTBEAT_INTERVAL = 10000; // 10 seconds
  const LEAVE_CALL_SELECTOR = `button[aria-label="Leave call"]`;

  class GoogleMeetMonitor {
    constructor() {
      this.inMeeting = false;
      this.startObserver = null;
      this.endObserver = null;
      this.heartbeatInterval = null;
    }

    // Network communication methods
    async sendStart() {
      try {
        await fetch(`${ENDPOINT}/meeting-start`, { method: "POST" });
      } catch (err) {
        console.error("meet‑start error", err);
      }
    }

    async sendEnd() {
      try {
        if (navigator.sendBeacon) {
          navigator.sendBeacon(`${ENDPOINT}/meeting-end`);
        } else {
          await fetch(`${ENDPOINT}/meeting-end`, {
            method: "POST",
            keepalive: true,
          });
        }
      } catch (err) {
        console.error("meet‑end error", err);
      }
    }

    async sendHeartbeat() {
      if (!this.inMeeting) return;

      try {
        await fetch(`${ENDPOINT}/meeting-heartbeat`, { method: "POST" });
      } catch (err) {
        console.error("meet‑heartbeat error", err);
      }
    }

    // State management methods
    async onMeetingStart() {
      if (this.inMeeting) return;

      this.inMeeting = true;
      console.debug("🎯 Meeting detected, sending start signal");
      await this.sendStart();

      this.stopStartObserver();
      this.startEndObserver();
      this.startHeartbeat();
      this.enableChatSideSwitch();
    }

    enableChatSideSwitch() {
      const element = document.createElement("button");
      document.body.appendChild(element);
      element.style.setProperty("position", "absolute");
      element.style.setProperty("top", "16px");
      element.style.setProperty("left", "50%");
      element.style.setProperty("transform", "translateX(-50%)");
      element.style.setProperty("background", "var(--gm3-sys-color-primary)");
      element.style.setProperty("color", "var(--gm3-sys-color-on-primary)");
      element.style.setProperty("z-index", "899999");
      element.style.setProperty("border-radius", "999999px");
      element.style.setProperty("padding", "12px 16px");
      element.style.setProperty("border", "none");
      element.dataset.side = "right";
      element.innerText = "Swap Sides";
      element.onclick = () => {
        const [top, right, bottom, left] = document.querySelector("main").style.inset.split(" ");
        if (left === undefined) {
          element.dataset.side = "right";
          return;
        }
        document.querySelector("main").style.inset = `${top} ${left} ${bottom} ${right}`;
        if (element.dataset.side === "right") {
          document.querySelector("aside").style.removeProperty("right");
          document.querySelector("aside").style.left = "16px";
          element.dataset.side = "left";
        } else {
          document.querySelector("aside").style.removeProperty("left");
          document.querySelector("aside").style.right = "16px";
          element.dataset.side = "right";
        }
      };
    }

    async onMeetingEnd() {
      if (!this.inMeeting) return;

      this.inMeeting = false;
      console.debug("🏁 Meeting ended, sending end signal");
      await this.sendEnd();

      this.stopEndObserver();
      this.stopHeartbeat();
      this.startStartObserver();
    }

    // Observer management methods
    startStartObserver() {
      if (this.startObserver) return;

      console.debug("👀 Starting observer for meeting start");
      this.startObserver = new MutationObserver(() => {
        const btn = document.querySelector(LEAVE_CALL_SELECTOR);
        if (btn) {
          this.onMeetingStart();
        }
      });

      this.startObserver.observe(document.body, {
        childList: true,
        subtree: true,
      });
    }

    stopStartObserver() {
      if (this.startObserver) {
        this.startObserver.disconnect();
        this.startObserver = null;
        console.debug("⏹️ Stopped start observer");
      }
    }

    startEndObserver() {
      if (this.endObserver) return;

      console.debug("👀 Starting observer for meeting end");
      this.endObserver = new MutationObserver(() => {
        const btn = document.querySelector(LEAVE_CALL_SELECTOR);
        if (!btn) {
          this.onMeetingEnd();
        }
      });

      this.endObserver.observe(document.body, {
        childList: true,
        subtree: true,
      });
    }

    stopEndObserver() {
      if (this.endObserver) {
        this.endObserver.disconnect();
        this.endObserver = null;
        console.debug("⏹️ Stopped end observer");
      }
    }

    // Heartbeat management methods
    startHeartbeat() {
      if (this.heartbeatInterval) return;

      console.debug("💓 Starting heartbeat with 10s intervals");
      this.heartbeatInterval = setInterval(() => {
        this.sendHeartbeat();
      }, HEARTBEAT_INTERVAL);
    }

    stopHeartbeat() {
      if (this.heartbeatInterval) {
        clearInterval(this.heartbeatInterval);
        this.heartbeatInterval = null;
        console.debug("💓 Stopped heartbeat");
      }
    }

    // Cleanup method
    cleanup() {
      this.stopStartObserver();
      this.stopEndObserver();
      this.stopHeartbeat();
      console.debug("⏹️ Stopped all observers and heartbeat");
    }

    // Initialization method
    async initialize() {
      if (!document.body) {
        setTimeout(() => this.initialize(), 500);
        return;
      }

      console.debug("⏱️ Initializing Google Meet monitoring");

      // Check if already in a meeting
      const btn = document.querySelector(LEAVE_CALL_SELECTOR);
      if (btn) {
        await this.onMeetingStart();
      } else {
        this.startStartObserver();
      }
    }

    // Cleanup on page unload
    handleUnload() {
      this.cleanup();
      if (this.inMeeting) {
        this.sendEnd();
      }
    }
  }

  // Initialize the monitor
  const monitor = new GoogleMeetMonitor();

  // Start monitoring when DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => monitor.initialize());
  } else {
    monitor.initialize();
  }

  // Clean up when page is unloaded
  window.addEventListener("beforeunload", () => monitor.handleUnload());
})();
