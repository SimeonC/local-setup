// ==UserScript==
// @name        Semaphore
// @namespace   Local Scripts
// @match       *://tablecheck.semaphore.com/*
// @grant       none
// @version     1.0
// @author      -
// @description 10/2/2025, 4:07:53 PM
// ==/UserScript==
(() => {
  const css = /* CSS */ `
.job-log-line-timestamp {
  user-select: none;
}
`;
  const style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);
})();

// CRON timestamp conversion

function convertCronNext(node) {
  const date = new Date(node.innerText);
  node.innerText = date.toString();
}
function convertCronWhen(element) {
  if (element.hasAttribute("cron-when-localised")) return;
  const textContent = element.textContent;
  const matches = textContent.match(/\d{2}:\d{2} [AP]M/gi);
  const interpolation = textContent.split(/\d{2}:\d{2} [AP]M/i);
  if (matches) {
    const replacements = matches.map(function (match) {
      const utcTime = new Date(`1970-01-01 ${match} Z`);
      return utcTime.toLocaleTimeString(undefined, {
        hour: "2-digit",
        minute: "2-digit",
      });
    });

    let newContent = "";
    while (replacements.length || interpolation.length) {
      newContent +=
        (interpolation.shift() || "") + (replacements.shift() || "");
    }
    element.textContent = newContent;
    element.setAttribute("cron-when-localised", "true");
  }
}

function convertNode(node) {
  if (node.hasAttribute("cron-when")) {
    convertCronWhen(node);
  }
  if (node.hasAttribute("cron-next")) {
    convertCronNext(node);
  }
}

const observer = new MutationObserver(function (mutationsList) {
  mutationsList.forEach(function (mutation) {
    if (mutation.type === "childList") {
      mutation.addedNodes.forEach(function (node) {
        if (node.nodeType !== Node.ELEMENT_NODE) return;
        convertNode(node);
      });
    } else if (mutation.type === "characterData") {
      convertNode(mutation.target.parentElement);
    }
  });
});

// Start observing changes in the DOM
document.onreadystatechange = () => {
  observer.observe(document.body, {
    childList: true,
    characterData: true,
    subtree: true,
  });
  document.querySelectorAll("[cron-when]").forEach(convertCronWhen);
  document.querySelectorAll("[cron-next]").forEach(convertCronNext);
};

// Notifications
document.addEventListener("DOMContentLoaded", () => {
  const project = document.querySelector(
    '#main-content a[href^="/projects"]'
  ).innerText;
  const [workflowType, workflowName] = document
    .querySelector('#main-content > div:nth-child(2) a[href^="/branches"]')
    .parentElement.innerText.split("\n");

  class CurrentStatuses {
    constructor() {
      this.pendingIds = [];
      this.getStatuses();
    }

    sendStatusUpdates() {
      this.getStatuses();
      this.sendNotifications();
    }

    getStatuses() {
      const pipelineNodes = this.getPipelineNodes();
      this.parsePipelineNodes(pipelineNodes);
    }

    getPipelineNodes() {
      return Array.from(
        document.querySelectorAll("#workflow-tree-container > div > div")
      );
    }

    parsePipelineNodes(nodes) {
      const mappedNodes = nodes.map((node) => this.parsePipelineNode(node));
      this.updatePipelines(mappedNodes);
    }

    parsePipelineNode(node) {
      return {
        id: node.dataset.pipelineId,
        ...this.parsePipelineText(node),
      };
    }

    parsePipelineText(node) {
      const divChildren = Array.from(node.childNodes).filter((node) =>
        this.isDiv(node)
      );
      const [status, name] = divChildren.map((node) => node.innerHTML);
      return { status, name };
    }

    isDiv(node) {
      return node.tagName && node.tagName.toLowerCase() === "div";
    }

    updatePipelines(pipelines) {
      this.pipelines = pipelines.reduce((result, pipeline) => {
        result[pipeline.id] = pipeline;
        return result;
      }, {});
    }

    sendNotifications() {
      const pipelines = Object.values(this.pipelines);
      pipelines.forEach(({ id }) => {
        switch (this.getPipelineUpdate(id)) {
          case "new": {
            this.pendingIds.push(id);
            return;
          }
          case "done": {
            this.sendStatusNotification(id);
            this.pendingIds.splice(this.pendingIds.indexOf(id), 1);
            return;
          }
        }
      });
    }

    getPipelineUpdate(id) {
      const { status } = this.pipelines[id];
      const isRunning = status === "Running";
      const wasRunning = this.pendingIds.includes(id);
      const isNewlyRunning = isRunning && !wasRunning;
      const isFinished = !isRunning && wasRunning;
      if (isNewlyRunning) return "new";
      if (isFinished) return "done";
      return "no-change";
    }

    sendStatusNotification(id) {
      const { status, name } = this.pipelines[id];
      new Notification(`${status}: ${name}`, {
        body: `Project: ${project}\n${workflowType}: ${workflowName}`,
      });
    }
  }

  function observe(observer) {
    const node = document.getElementById("main-content");
    if (!node) return setTimeout(() => observe(observer), 100);
    observer.observe(node, {
      childList: true,
      subtree: true,
      characterData: true,
    });
  }

  Notification.requestPermission().then(() => {
    const statuses = new CurrentStatuses();
    const observer = new MutationObserver(() => {
      statuses.sendStatusUpdates();
    });
    observe(observer);
  });
});

// Semaphore Activity Monitor Filter Extension
(function () {
  "use strict";

  let activeFilters = {
    projects: new Set(),
    machines: new Set(),
  };

  let allProjects = new Set();
  let allMachines = new Set();
  let filterUICreated = false;

  // Extract project names from pipeline items
  function extractProjects() {
    const projectLinks = document.querySelectorAll(
      '#activity_monitor_active_items a[href^="/projects/"]'
    );
    const projects = new Set();

    projectLinks.forEach((link) => {
      const projectName = link.textContent.trim();
      if (projectName) {
        projects.add(projectName);
      }
    });

    return projects;
  }

  // Extract machine types from job stats
  function extractMachineTypes() {
    const machineSpans = document.querySelectorAll(
      "#activity_monitor_active_items .f5.mt1 .gray"
    );
    const machines = new Set();

    machineSpans.forEach((span) => {
      const text = span.textContent;
      // Extract machine types from text like "on s1-supernode-x86-large" or "on e1-standard-2"
      const machineMatches = text.match(/on\s+([\w-]+(?:,\s*[\w-]+)*)/g);
      if (machineMatches) {
        machineMatches.forEach((match) => {
          // Remove "on " and split by comma
          const machineList = match.replace("on ", "").split(",");
          machineList.forEach((machine) => {
            // Extract just the machine type, ignore parenthetical info
            const cleanMachine = machine.trim().split(" ")[0];
            if (cleanMachine) {
              machines.add(cleanMachine);
            }
          });
        });
      }
    });

    return machines;
  }

  // Create filter button element
  function createFilterButton(text, type, value, isActive = false) {
    const button = document.createElement("button");
    button.textContent = text;
    button.className = `filter-btn ${isActive ? "active" : ""}`;
    button.dataset.type = type;
    button.dataset.value = value;

    // Style the button
    updateButtonStyle(button, isActive);

    return button;
  }

  // Update button visual state
  function updateButtonStyle(button, isActive) {
    button.style.cssText = `
            margin: 2px;
            padding: 4px 8px;
            border: 1px solid #ccc;
            border-radius: 4px;
            background: ${isActive ? "#007acc" : "#f5f5f5"};
            color: ${isActive ? "white" : "#333"};
            cursor: pointer;
            font-size: 12px;
            transition: all 0.2s ease;
        `;
  }

  // Toggle filter state
  function toggleFilter(type, value) {
    const button = document.querySelector(
      `[data-type="${type}"][data-value="${value}"]`
    );
    if (!button) return;

    const isActive = button.classList.contains("active");

    if (isActive) {
      button.classList.remove("active");
      activeFilters[type].delete(value);
    } else {
      button.classList.add("active");
      activeFilters[type].add(value);
    }

    updateButtonStyle(button, !isActive);
    applyFilters();
  }

  // Apply filters to pipeline items
  function applyFilters() {
    const pipelineItems = document.querySelectorAll(
      "#activity_monitor_active_items > div"
    );

    pipelineItems.forEach((item) => {
      let shouldShow = true;

      // Check project filter
      if (activeFilters.projects.size > 0) {
        const projectLink = item.querySelector('a[href^="/projects/"]');
        const projectName = projectLink ? projectLink.textContent.trim() : "";
        shouldShow = shouldShow && activeFilters.projects.has(projectName);
      }

      // Check machine filter
      if (activeFilters.machines.size > 0 && shouldShow) {
        const machineSpan = item.querySelector(".f5.mt1 .gray");
        if (machineSpan) {
          const text = machineSpan.textContent;
          const machineMatches = text.match(/on\s+([\w-]+(?:,\s*[\w-]+)*)/g);

          let hasMachineMatch = false;
          if (machineMatches) {
            machineMatches.forEach((match) => {
              const machineList = match.replace("on ", "").split(",");
              machineList.forEach((machine) => {
                const cleanMachine = machine.trim().split(" ")[0];
                if (activeFilters.machines.has(cleanMachine)) {
                  hasMachineMatch = true;
                }
              });
            });
          }
          shouldShow = shouldShow && hasMachineMatch;
        }
      }

      // Show/hide item
      item.style.display = shouldShow ? "block" : "none";
    });

    // Update filter counts
    updateFilterCounts();
  }

  // Update filter button counts
  function updateFilterCounts() {
    const visibleItems = document.querySelectorAll(
      '#activity_monitor_active_items > div[style*="block"], #activity_monitor_active_items > div:not([style*="none"])'
    );
    const totalItems = document.querySelectorAll(
      "#activity_monitor_active_items > div"
    ).length;

    const statusDiv = document.querySelector("#filter-status");
    if (statusDiv) {
      statusDiv.textContent = `Showing ${visibleItems.length} of ${totalItems} items`;
    }
  }

  // Update existing buttons or create new ones
  function updateFilterButtons(container, type, items, currentItems) {
    const existingButtons = container.querySelectorAll(`[data-type="${type}"]`);
    const existingValues = new Set();

    // Update existing buttons and track what we have
    existingButtons.forEach((button) => {
      const value = button.dataset.value;
      existingValues.add(value);

      if (!items.has(value)) {
        // Remove button if item no longer exists
        button.remove();
      } else {
        // Update button state if it exists
        const isActive = activeFilters[type].has(value);
        button.className = `filter-btn ${isActive ? "active" : ""}`;
        updateButtonStyle(button, isActive);
      }
    });

    // Add new buttons for items we don't have yet
    Array.from(items)
      .sort()
      .forEach((item) => {
        if (!existingValues.has(item)) {
          const isActive = activeFilters[type].has(item);
          const button = createFilterButton(item, type, item, isActive);
          container.appendChild(button);
        }
      });
  }

  // Create or update filter UI
  function createOrUpdateFilterUI() {
    let filterContainer = document.querySelector("#activity-filter-ui");
    const activityItems = document.querySelector(
      "#activity_monitor_active_items"
    );

    if (!activityItems) return;

    // Get current data
    const newProjects = extractProjects();
    const newMachines = extractMachineTypes();

    // Create UI if it doesn't exist
    if (!filterContainer) {
      filterContainer = document.createElement("div");
      filterContainer.id = "activity-filter-ui";
      filterContainer.style.cssText = `
                background: #f8f9fa;
                border: 1px solid #dee2e6;
                border-radius: 6px;
                padding: 12px;
                margin-bottom: 16px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            `;

      // Clear filters button
      const clearAllBtn = document.createElement("button");
      clearAllBtn.textContent = "✕ Clear All Filters";
      clearAllBtn.id = "clear-all-filters";
      clearAllBtn.style.cssText = `
                margin: 2px 8px 8px 0;
                padding: 6px 12px;
                border: 1px solid #dc3545;
                border-radius: 4px;
                background: #dc3545;
                color: white;
                cursor: pointer;
                font-size: 12px;
                font-weight: bold;
            `;

      // Status display
      const statusDiv = document.createElement("div");
      statusDiv.id = "filter-status";
      statusDiv.style.cssText = `
                font-size: 12px;
                color: #666;
                margin: 4px 0;
                font-weight: bold;
            `;

      // Project filters section
      const projectSection = document.createElement("div");
      projectSection.style.marginBottom = "8px";

      const projectLabel = document.createElement("div");
      projectLabel.textContent = "📁 Filter by Project:";
      projectLabel.style.cssText = `
                font-weight: bold;
                margin-bottom: 4px;
                font-size: 13px;
                color: #333;
            `;

      const projectButtons = document.createElement("div");
      projectButtons.id = "project-buttons";

      // Machine filters section
      const machineSection = document.createElement("div");

      const machineLabel = document.createElement("div");
      machineLabel.textContent = "🖥️ Filter by Machine Type:";
      machineLabel.style.cssText = `
                font-weight: bold;
                margin-bottom: 4px;
                font-size: 13px;
                color: #333;
            `;

      const machineButtons = document.createElement("div");
      machineButtons.id = "machine-buttons";

      // Assemble UI
      filterContainer.appendChild(clearAllBtn);
      filterContainer.appendChild(statusDiv);
      projectSection.appendChild(projectLabel);
      projectSection.appendChild(projectButtons);
      filterContainer.appendChild(projectSection);
      machineSection.appendChild(machineLabel);
      machineSection.appendChild(machineButtons);
      filterContainer.appendChild(machineSection);

      // Insert before activity items
      activityItems.parentNode.insertBefore(filterContainer, activityItems);

      filterUICreated = true;
    }

    // Update button containers
    const projectButtons = document.querySelector("#project-buttons");
    const machineButtons = document.querySelector("#machine-buttons");

    if (projectButtons && machineButtons) {
      updateFilterButtons(projectButtons, "projects", newProjects, allProjects);
      updateFilterButtons(machineButtons, "machines", newMachines, allMachines);
    }

    // Update stored data
    allProjects = newProjects;
    allMachines = newMachines;

    // Update counts
    updateFilterCounts();
  }

  // Clear all filters
  function clearAllFilters() {
    activeFilters.projects.clear();
    activeFilters.machines.clear();

    // Reset all buttons
    document.querySelectorAll(".filter-btn").forEach((button) => {
      button.classList.remove("active");
      updateButtonStyle(button, false);
    });

    applyFilters();
  }

  // Set up event delegation for filter UI
  function setupEventDelegation() {
    // Use event delegation on document for filter buttons
    document.addEventListener("click", (e) => {
      // Handle filter buttons
      if (e.target.classList.contains("filter-btn")) {
        const type = e.target.dataset.type;
        const value = e.target.dataset.value;
        toggleFilter(type, value);
        return;
      }

      // Handle clear all button
      if (e.target.id === "clear-all-filters") {
        clearAllFilters();
        return;
      }
    });

    // Handle hover effects for filter buttons
    document.addEventListener(
      "mouseenter",
      (e) => {
        if (
          e.target.classList.contains("filter-btn") &&
          !e.target.classList.contains("active")
        ) {
          e.target.style.background = "#e0e0e0";
        }
      },
      true
    );

    document.addEventListener(
      "mouseleave",
      (e) => {
        if (
          e.target.classList.contains("filter-btn") &&
          !e.target.classList.contains("active")
        ) {
          e.target.style.background = "#f5f5f5";
        }
      },
      true
    );
  }

  // Add click handlers to machine quota displays for filtering
  function setupMachineQuotaClickHandlers() {
    // Remove existing listeners by cloning nodes (this removes all event listeners)
    const machineQuotas = document.querySelectorAll(
      "#activity-monitor-gauges .w5-ns, #activity-monitor-self-hosted-gauges .w5-ns"
    );

    machineQuotas.forEach((quota) => {
      // Skip if already processed
      if (quota.dataset.clickHandlerAdded) return;

      const machineNameElement = quota.querySelector("h2");
      if (machineNameElement) {
        const machineName = machineNameElement.textContent.trim();

        // Make it look clickable
        quota.style.cursor = "pointer";
        quota.style.transition = "transform 0.2s ease, box-shadow 0.2s ease";
        quota.dataset.clickHandlerAdded = "true";
        quota.dataset.machineName = machineName;

        // Add hover effect
        quota.addEventListener("mouseenter", () => {
          quota.style.transform = "scale(1.02)";
          quota.style.boxShadow = "0 4px 12px rgba(0,0,0,0.15)";
        });

        quota.addEventListener("mouseleave", () => {
          quota.style.transform = "scale(1)";
          quota.style.boxShadow = "";
        });
      }
    });

    // Use event delegation for machine quota clicks
    document.addEventListener("click", (e) => {
      const quota = e.target.closest("[data-machine-name]");
      if (quota && quota.dataset.machineName) {
        toggleFilter("machines", quota.dataset.machineName);
      }
    });
  }

  // Debounced update function
  let updateTimeout;
  function debouncedUpdate() {
    clearTimeout(updateTimeout);
    updateTimeout = setTimeout(() => {
      createOrUpdateFilterUI();
      setupMachineQuotaClickHandlers();
      applyFilters();
    }, 100);
  }

  // Mutation observer to handle dynamic content updates
  function setupMutationObserver() {
    const targetNode = document.querySelector("#activity_monitor_active_items");
    if (!targetNode) return;

    const observer = new MutationObserver((mutations) => {
      let shouldUpdate = false;

      mutations.forEach((mutation) => {
        // Check if nodes were added or removed
        if (
          mutation.type === "childList" &&
          (mutation.addedNodes.length > 0 || mutation.removedNodes.length > 0)
        ) {
          shouldUpdate = true;
        }

        // Also check for text content changes
        if (mutation.type === "characterData") {
          shouldUpdate = true;
        }
      });

      if (shouldUpdate) {
        debouncedUpdate();
      }
    });

    observer.observe(targetNode, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    // Also observe the main activity monitor container for broader changes
    const activityContainer = document.querySelector("#activity-monitor-items");
    if (activityContainer) {
      observer.observe(activityContainer, {
        childList: true,
        subtree: true,
      });
    }

    // Observe machine quota containers for changes
    const gaugeContainers = document.querySelectorAll(
      "#activity-monitor-gauges, #activity-monitor-self-hosted-gauges"
    );
    gaugeContainers.forEach((container) => {
      if (container) {
        observer.observe(container, {
          childList: true,
          subtree: true,
        });
      }
    });
  }

  // Initialize the filter system
  function init() {
    // Wait for DOM to be ready
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init);
      return;
    }

    // Set up event delegation first (only once)
    setupEventDelegation();

    // Wait a bit for any dynamic content to load
    setTimeout(() => {
      createOrUpdateFilterUI();
      setupMachineQuotaClickHandlers();
      setupMutationObserver();
    }, 500);
  }

  // Start the extension
  init();

  // Also expose functions globally for debugging
  window.semaphoreFilter = {
    createOrUpdateFilterUI,
    clearAllFilters,
    activeFilters,
    allProjects,
    allMachines,
    toggleFilter,
  };
})();
