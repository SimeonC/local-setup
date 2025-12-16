// ==UserScript==
// @name        Jira atlassian.net
// @namespace   Local Scripts
// @match       https://tablecheck.atlassian.net/jira/*
// @grant       none
// @version     1.0
// @author      -
// @description 10/2/2025, 4:07:53 PM
// ==/UserScript==
(() => {
  const css = /* CSS */ `
    #jira-card-hover-toggle input {
      display: none;
    }
    #jira-card-hover-toggle {
      display: none;
      padding: 8px 12px;
      position: fixed;
      bottom: 12px;
      left: 12px;
      border: 1px solid var(--border, #E5E5E5);
      background: var(--background, white);
      border-radius: 4px;
      z-index: 99999999;
      cursor: pointer;
    }

    #jira-card-hover-toggle:has( :checked) {
      --border: #7935D2;
      --background: #E6DBF3;
    }

    body:has( [data-testid="platform-board-kit.ui.card.card"]) #jira-card-hover-toggle {
      display: block;
    }

    [data-testid="platform-board-kit.ui.column.draggable-column.styled-wrapper"]
      > :first-child
      > :first-child
      > :nth-child(2):has( [data-testid="common-components-status-lozenge.status-lozenge"]) > * {
        height: calc(100vh - 300px) !important;
        min-height: calc(100vh - 300px) !important;
    }

    [data-testid="platform-board-kit.ui.column.draggable-column.styled-wrapper"]
      > :first-child
      > :first-child
      > :nth-child(1):has( [data-testid="common-components-status-lozenge.status-lozenge"]) > * {
        height: 100%;
        min-height: 100%;
    }

    body:has( #jira-card-hover-toggle :checked) [data-testid="platform-board-kit.ui.card.card"] > div {
      background: white;
    }

    body:has( #jira-card-hover-toggle :checked) [data-testid="platform-board-kit.ui.card.card"]:before {
      --angle: 0deg;
      --border: -1vmin;
      --brightness: 3;
      --blur: 3vmin;
      --speed: 8s;
      --color-one: #7935D2;
      --color-two: #8043cf;
      --color-three: #5c28a0;
      --color-four: #771bf0;
      content: "";
      background: conic-gradient(from var(--angle), var(--color-one) 25%, var(--color-two) 50%, var(--color-three) 75%, var(--color-four));
      position: absolute;
      inset: var(--border);
      filter: blur(var(--blur)) brightness(var(--brightness));
      z-index: -1;
      opacity: 0;
      transition: opacity 300ms ease-in-out;
    }

    body:has( #jira-card-hover-toggle :checked) [data-testid="platform-board-kit.ui.card.card"]:hover:before {
      opacity: 0.7;
    }
    body:has( #jira-card-hover-toggle :checked) [data-testid="platform-board-kit.ui.card.card"]:hover {
      z-index: 9999999;
    }

    body:has( #jira-card-hover-toggle :checked) [data-testid="software-board.board-container.board.virtual-board.fast-virtual-list.fast-virtual-list-wrapper"]:has( [data-test-id="platform-board-kit.ui.card.card"]:hover) {
      contain: layout !important;
    }

    body:has( #jira-card-hover-toggle :checked):has( [data-testid="platform-board-kit.ui.card.card"]:hover) div:has( > [data-test-id="platform-board-kit.common.ui.column-header.header.column-header-container"]) {
      z-index: 0;
    }

    body:has( #jira-card-hover-toggle :checked):has( [data-testid="platform-board-kit.ui.card.card"]:hover) [data-test-id="platform-board-kit.ui.swimlane.swimlane-wrapper"] > [role="button"] {
      z-index: 0 !important;
      background: transparent;
    }
    body:has( #jira-card-hover-toggle :checked):has( [data-test-d="platform-board-kit.ui.card.card"]:hover) [data-test-id="platform-board-kit.ui.swimlane.swimlane-wrapper"] > [role="button"] > * > * {
      background: transparent;
    }
    body:has( #jira-card-hover-toggle :checked):has( [data-testid="platform-board-kit.ui.card.card"]:hover) [data-test-id="platform-board-kit.ui.swimlane.swimlane-wrapper"] > :first-child,
    body:has( #jira-card-hover-toggle :checked):has( [data-testid="platform-board-kit.ui.card.card"]:hover) [data-test-id="platform-board-kit.ui.swimlane.swimlane-wrapper"] > :nth-child(2) {
      background: transparent;
    }

    body:has( #jira-card-hover-toggle :checked) [data-testid="platform-board-kit.ui.column.draggable-column.styled-wrapper"]:has( [data-test-id="platform-board-kit.ui.card.card"]:hover) {
      z-index: 8;
    }


    @supports (background: paint(houdini)) {
      @property --angle {
        syntax: '<angle>';
        initial-value: 0deg;
        inherits: true;
      }

      [data-test-id="platform-board-kit.ui.card.card"]:before {
        animation: rotate-background-custom var(--speed) infinite linear reverse;
      }

      @keyframes rotate-background-custom {
        to {
          --angle: 360deg;
        }
      }
    }
    `;
  const style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);
})();

const label = document.createElement("label");
label.setAttribute("id", "jira-card-hover-toggle");
label.innerHTML = "Toggle Hover";
const checkbox = document.createElement("input");
checkbox.setAttribute("type", "checkbox");
const storageKey = "__arc-plugin__jira-card-hover-toggle";
if (localStorage.getItem(storageKey) === "on") {
  checkbox.setAttribute("checked", "checked");
}
checkbox.addEventListener("change", (e) => {
  localStorage.setItem(storageKey, e.currentTarget.checked ? "on" : "off");
});
label.append(checkbox);
document.addEventListener("DOMContentLoaded", () => {
  document.body.append(label);
});
