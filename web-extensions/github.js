// ==UserScript==
// @name        Github Upgrades
// @namespace   Local Scripts
// @match       https://github.com/*
// @grant       none
// @version     1.4.8
// @author      -
// @description 9/10/2025, 2:59:24 PM
// ==/UserScript==
(() => {
  const css = /* CSS */ `
  body, .markdown-body, body .blob-code-inner {
    font-family: "Fira Code" !important;
  }
  body tt, body code, body samp, body kbd, body pre {
    font-family:    "Fira Code" !important;
  }
  :root, body {
    --fontStack-monospace: "Fira Code" !important;
    --fontStack-sansSerif: "Fira Code" !important;
    --fontStack-system:      "Fira Code" !important;
  }

  #notification-shelf {
    background-image: linear-gradient(var(--bgColor-accent-muted, var(--color-accent-subtle)), var(--bgColor-accent-muted, var(--color-accent-subtle))) !important;
  }
  #notification-shelf ~ .application-main .sticky-file-header {
    top: 129px !important;
    border-radius: 0 !important;
  }

  #notification-shelf ~ .application-main .pr-toolbar.js-sticky-is-stuck {
    top: 69px !important;
    background-color: var(--bgColor-default, var(--color-canvas-default));
    border-bottom: var(--borderWidth-thin) solid var(--borderColor-muted, var(--color-border-muted));
    box-shadow: var(--shadow-resting-medium);
  }
  `;
  const style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);
})();

// change the following two key combos as you like
// this key combo will mark the current focused file as viewed and jump to the next unviewed file
const viewedAndNextKey = "v";
// this key combo will just jump to the next unviewed file
const nextKey = "w";
// this key combo marks all files as "viewed"
const markAllViewed = "z";

// edit this function to work however you need it to, return undefined to not show the deployment tag
function branchNameToDeploymentHref(branchName) {
  try {
    if (window.location.href.includes("/settings-frontend/"))
      return `https://app.staging-qa.tablecheck.com/s/${branchName
        .toLowerCase()
        .replace(/[^a-z0-9-]+/gi, "-")}`;
    if (window.location.href.includes("/manager-ember"))
      return `https://manager.app.staging-qa.tablecheck.com/branches/${branchName.toLowerCase()}/index.html`;
  } catch (e) {
    console.error("Arc Boost", e);
  }
  return undefined;
}

function testKey(event, key) {
  return `key${key}` === event.code.toLowerCase() || key === event.key.toLowerCase();
}

function testEvent(event) {
  if (!event.ctrlKey || !event.altKey || !event.metaKey || !event.shiftKey) return false;
  if (testKey(event, viewedAndNextKey)) return "view";
  if (testKey(event, nextKey)) return "next";
  if (testKey(event, markAllViewed)) return "all";
  return false;
}

function getAllReviewElements() {
  const result = [];
  document.querySelectorAll("[role=region]").forEach((e) => {
    const button = e.querySelector("button[aria-pressed]");
    if (!button) return;
    const isViewed = button.getAttribute("aria-pressed") === "true";
    result.push({
      filePath: e.querySelector("h3").innerText,
      isViewed,
      isActive: document.activeElement === button,
      markViewed: () => (isViewed ? undefined : button.click()),
      focus: () =>
        setTimeout(() => {
          button.focus();
          const elementPosition = e.getBoundingClientRect().top;
          let offsetPosition = elementPosition + window.pageYOffset - 120;
          const elNotif = document.querySelector(".notification-shelf");
          if (elNotif) {
            offsetPosition -= elNotif.getBoundingClientRect().height;
          }
          window.scrollTo({
            top: offsetPosition,
            behavior: "auto",
          });
        }, 400),
    });
  });
  return result;
}

function selectReviewRadio(value) {
  const el = document.querySelector(`[name=reviewEvent][value="${value}"]`);
  if (!el) return;
  el.click();
}

function finishReview() {
  document.querySelector(`section button[data-variant="primary"]`).click();
  setTimeout(() => {
    const reviewComments = document.querySelectorAll(
      `[aria-labelledby="anchored-review-title"] details [class^="UnifiedDiffLines"]`,
    );
    selectReviewRadio(reviewComments.length ? "request changes" : "approve");
  }, 200);
}

window.addEventListener("keydown", (event) => {
  const commandType = testEvent(event);
  evaluateCommand(commandType);
});

function pageIsLoading() {
  return document.querySelectorAll("[class*=LoadingSkeleton]").length > 0;
}

let lastCommand;

function evaluatePendingCommand() {
  evaluateCommand(lastCommand);
}

function storePendingCommandOrExec(c, f = () => {}) {
  if (!pageIsLoading()) return f();
  lastCommand = c;
  waitForPageToLoad();
}

let pageLoadTimeout;
function waitForPageToLoad() {
  if (pageLoadTimeout) return;
  pageLoadTimeout = setTimeout(() => {
    pageLoadTimeout = undefined;
    if (pageIsLoading()) {
      return waitForPageToLoad();
    }
    evaluatePendingCommand();
  }, 1000);
}

function evaluateCommand(commandType) {
  if (!commandType) return;
  lastCommand = undefined;
  const allReviews = getAllReviewElements();
  if (!allReviews.length) return storePendingCommandOrExec(commandType);
  if (commandType === "view" || commandType === "next") {
    let foundActive = false;
    let next;
    let first;
    for (const r of allReviews) {
      if (!isReviewable(r)) {
        if (!r.isViewed) r.markViewed();
        continue;
      }
      if (foundActive) {
        next = r;
        first = first ?? r;
        break;
      }
      if (r.isActive) {
        foundActive = true;
        if (commandType === "view") {
          r.markViewed();
        }
      } else if (!first && !r.isViewed) {
        first = r;
      }
    }
    if (!first) return storePendingCommandOrExec(commandType, finishReview);
    (next || first).focus();
  }
  if (commandType === "all") {
    allReviews.forEach((r) => r.markViewed());
    storePendingCommandOrExec(commandType, finishReview);
  }
}

function splitAndSeparateLast(string, separator) {
  const parts = string.split(separator);
  const last = parts.slice(-1)[0];
  const rest = parts.slice(0, -1);
  return {
    last,
    rest,
  };
}

/**
 *
 * @param {*} r review element
 */
function isReviewable(r) {
    const { filePath, isViewed } = r;
    if (isViewed) return false;
    const { last: fileName, rest: directories } = splitAndSeparateLast(filePath, "/");
    const { last: ext, rest: fileNameParts } = splitAndSeparateLast(fileName, ".");
    if (
      ext !== "json" ||
      !directories.some((folder) => ["i18n", "locale", "locales"].includes(folder))
    )
      return true;
    const isReviewable = ["en", "ja"].some(
      (l) => fileNameParts.includes(l) || directories.includes(l),
    );
    return isReviewable;
}

function getContainers() {
  return Array.from(
    document.querySelectorAll(
      `div:has(>.head-ref),[class*=StateLabel] + div > *:has(a[href^="/tablecheck/"]),div:has(>[class*=StateLabel]) ~ div > *:has(a[href^="/tablecheck/"])`,
    ),
  ).map((c, i) => ({
    id: "new-pr-" + i,
    add: (n) => c.append(n),
    element: c,
  }));
}

function buildButton({ id, href, text }) {
  const linkButton = document.createElement("a");
  linkButton.setAttribute("id", id);
  linkButton.classList.add("btn", "btn-sm", "mr-3");
  linkButton.setAttribute("target", "_blank");
  linkButton.setAttribute("rel", "noopener noreferrer");
  linkButton.setAttribute("href", href);
  linkButton.innerHTML = text;
  return linkButton;
}

function addButtonLinkToContainer({ id, getOptions, container: { id: containerId, add, element } }) {
  const compoundId = id + containerId;
  if (document.getElementById(compoundId)) return true;
  const options = getOptions(element);
  if (!options) return false;
  if (Array.isArray(options)) {
    const newOptions = options.filter(({ id }) => !document.getElementById(compoundId + id));
    newOptions.forEach(({ text, href, id }) => {
      add(buildButton({ id: compoundId + id, href, text }));
    });
    return newOptions.length > 0;
  }
  const { text, href } = options;
  add(buildButton({ id: compoundId, href, text }));
  return true;
}

function addButtonLink(containers, { id, getOptions }) {
  return containers
    .map((container) => addButtonLinkToContainer({ id, getOptions, container }))
    .some((v) => !!v);
}

const jiraRegex = /(?:^|-|\/|\[|\s)(?<ticket>[a-zA-Z]{3,}-[0-9]+)/i;
const globalJiraRegex = /(?:^|-|\/|\[|\s)(?<ticket>[a-zA-Z]{3,}-[0-9]+)/gi;
const branchTagSelector = `[href*="/tree/"]`;
let allHeaderButtonsAdded = false;
function addHeaderButtons() {
  if (allHeaderButtonsAdded) return true;
  const containers = getContainers();
  allHeaderButtonsAdded = [
    addButtonLink(containers, {
      id: "header-deployments-link",
      getOptions: (element) => {
        const branchLink = Array.from(element.querySelectorAll(branchTagSelector)).at(-1);
        if (!branchLink) return;
        const branchParts = branchLink.getAttribute("href").split("/");
        const branchName = branchParts[branchParts.length - 1];
        const href = branchNameToDeploymentHref(branchName);
        if (!href) return;
        return {
          href: href,
          text: "View deployment",
        };
      },
    }),
    addButtonLink(containers, {
      id: "jira-issue-link",
      getOptions: () => {
        const branchLink = document.querySelector(branchTagSelector)?.getAttribute("href");
        const jiraLinks = Array.from(
          document.querySelectorAll(`[href^="https://tablecheck.atlassian.net/browse/"]`),
        ).map((e) => {
          if (e.closest("code") || e.closest(".TimelineItem")) return false;
          const containingP = e.closest("p");
          if (containingP && containingP.textContent.match(/example:/i)) return false;
          return e.getAttribute("href");
        });
        const header = document.querySelector(
          `[data-component="PH_Title"],.gh-header-title`,
        )?.textContent;
        const linkMatches = [branchLink].concat(jiraLinks).map((i) => {
          if (!i) return undefined;
          const match = i.match(jiraRegex);
          return match?.groups?.ticket;
        });
        const allMatches = linkMatches
          .concat(
            header ? Array.from(header.matchAll(globalJiraRegex)).map((m) => m.groups?.ticket) : [],
          )
          .filter((i) => !!i);
        const uniqueMatches = Array.from(new Set(allMatches.map((s) => s?.toUpperCase())).values());
        return uniqueMatches.map((l) => ({
          id: l,
          href: `https://tablecheck.atlassian.net/browse/${l}`,
          text: l,
        }));
      },
    }),
  ].every((v) => !!v);
}

document.addEventListener(`pointerdown`, (e) => {
  if (e.currentTarget.tagName === `A` && e.currentTarget.getAttribute(`href`)?.startsWith(`https://cursor.com/open/`)) {
    e.currentTarget.setAttribute(`target`, `_blank`);
  }
});

let headerButtonsInterval;
function setupDom() {
  if (headerButtonsInterval) return;
  addHeaderButtons();
  headerButtonsInterval = setInterval(() => {
    addHeaderButtons();
  }, 5000);
}

window.addEventListener("click", (e) => {
  if (
    e.target.classList.contains("tabnav-tab") ||
    e.target.parentElement.classList.contains("tabnav-tab")
  ) {
    setupDom();
  }
});

setTimeout(() => {
  setupDom();
}, 600);
