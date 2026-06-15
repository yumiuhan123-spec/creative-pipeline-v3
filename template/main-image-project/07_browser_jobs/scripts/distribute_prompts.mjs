import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { pathToFileURL } from "node:url";

function parseArgs(argv) {
  const result = { command: argv[2] };
  for (let i = 3; i < argv.length; i += 2) {
    if (!argv[i]?.startsWith("--") || argv[i + 1] === undefined) {
      throw new Error(`Invalid argument near ${argv[i] ?? "<end>"}`);
    }
    result[argv[i].slice(2)] = argv[i + 1];
  }
  return result;
}

async function loadPlaywright() {
  try {
    return await import("playwright");
  } catch (firstError) {
    const roots = [
      process.env.CODEX_NODE_MODULES,
      path.join(
        process.env.LOCALAPPDATA ?? os.homedir(),
        "CreativePipelineV3",
        "runtime",
        "node_modules"
      ),
      path.join(
        os.homedir(),
        ".cache",
        "codex-runtimes",
        "codex-primary-runtime",
        "dependencies",
        "node",
        "node_modules"
      ),
    ].filter(Boolean);
    for (const root of roots) {
      const candidates = [path.join(root, "playwright", "index.mjs")];
      const pnpmRoot = path.join(root, ".pnpm");
      try {
        const entries = await fs.readdir(pnpmRoot);
        const pkg = entries.find((entry) => entry.startsWith("playwright@"));
        if (pkg) {
          candidates.unshift(
            path.join(pnpmRoot, pkg, "node_modules", "playwright", "index.mjs")
          );
        }
      } catch {
        // Not a pnpm runtime.
      }
      for (const candidate of candidates) {
        try {
          await fs.access(candidate);
          return await import(pathToFileURL(candidate).href);
        } catch {
          // Try the next candidate.
        }
      }
    }
    throw new Error(`Playwright is unavailable: ${firstError.message}`);
  }
}

async function readJson(file) {
  return JSON.parse(await fs.readFile(file, "utf8"));
}

async function writeJson(file, value) {
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function appendLog(file, value) {
  await fs.appendFile(file, `${JSON.stringify(value)}\n`, "utf8");
}

function now() {
  return new Date().toISOString();
}

function resolveInside(root, relative) {
  const resolved = path.resolve(root, relative);
  const base = `${path.resolve(root)}${path.sep}`.toLowerCase();
  if (!`${resolved}${path.sep}`.toLowerCase().startsWith(base)) {
    throw new Error(`Path escapes project directory: ${relative}`);
  }
  return resolved;
}

function approval(status, key) {
  return Boolean(status?.approvals?.[key] ?? status?.[key]);
}

async function validateProject(projectDir, allowDryRun) {
  const status = await readJson(path.join(projectDir, "00_project", "status.json"));
  const promptIndex = await readJson(path.join(projectDir, "06_prompts", "prompt_index.json"));
  const manifest = await readJson(path.join(projectDir, "07_browser_jobs", "batch_manifest.json"));

  const errors = [];
  if (!allowDryRun) {
    if (promptIndex.status !== "approved") errors.push("prompt_index.json is not approved.");
    if (!approval(status, "prompts_approved")) errors.push("prompts_approved is false.");
    if (!approval(status, "browser_submission_approved")) {
      errors.push("browser_submission_approved is false.");
    }
    if (manifest.submit !== true) errors.push("batch_manifest.json submit is not true.");
  }
  if (!Array.isArray(manifest.jobs) || manifest.jobs.length !== 6) {
    errors.push("batch_manifest.json must contain exactly six jobs.");
  }

  const jobs = [];
  for (const [index, job] of (manifest.jobs ?? []).entries()) {
    try {
      const promptPath = resolveInside(projectDir, job.prompt_file);
      const prompt = (await fs.readFile(promptPath, "utf8")).trim();
      if (!prompt || /\[等待|TODO|占位/.test(prompt)) {
        errors.push(`Job ${index + 1} has an empty or placeholder prompt.`);
      }
      const indexed = promptIndex.prompts?.find(
        (item) => Number(item.image) === Number(job.tab ?? index + 1)
      );
      const referenceFiles = job.reference_files ?? indexed?.reference_files ?? [];
      const resolvedReferences = [];
      for (const reference of referenceFiles) {
        const file = resolveInside(projectDir, reference);
        const stat = await fs.stat(file);
        if (!stat.isFile()) throw new Error(`Reference is not a file: ${reference}`);
        resolvedReferences.push(file);
      }
      jobs.push({
        number: index + 1,
        promptPath,
        prompt,
        referenceFiles: resolvedReferences,
      });
    } catch (error) {
      errors.push(`Job ${index + 1}: ${error.message}`);
    }
  }
  return { status, promptIndex, manifest, jobs, errors };
}

async function authState(page) {
  await page.goto("https://chatgpt.com/", {
    waitUntil: "domcontentloaded",
    timeout: 60000,
  });
  await page.waitForTimeout(1500);
  return page.evaluate(() => {
    const text = document.body?.innerText ?? "";
    return {
      authenticated:
        Boolean(document.querySelector('textarea, [contenteditable="true"]')) &&
        !/Log in|登录/.test(text),
      title: document.title,
      url: location.href,
    };
  });
}

function composer(page) {
  return page
    .locator('[data-testid="prompt-textarea"], textarea, div[contenteditable="true"]')
    .filter({ visible: true })
    .first();
}

async function uploadReferences(page, files) {
  if (!files.length) return;
  const fileInput = page.locator('input[type="file"]').first();
  if (await fileInput.count()) {
    await fileInput.setInputFiles(files);
    await page.waitForTimeout(1500);
    return;
  }
  const attach = page
    .locator(
      'button[aria-label*="Attach" i], button[aria-label*="上传"], button[aria-label*="添加"], [data-testid*="attach"]'
    )
    .filter({ visible: true })
    .first();
  if (!(await attach.count())) {
    throw new Error("ChatGPT file attachment control was not found.");
  }
  const chooserPromise = page.waitForEvent("filechooser", { timeout: 10000 });
  await attach.click();
  const chooser = await chooserPromise;
  await chooser.setFiles(files);
  await page.waitForTimeout(1500);
}

async function fillPrompt(page, text) {
  const input = composer(page);
  await input.waitFor({ state: "visible", timeout: 30000 });
  await input.fill(text);
}

async function sendButton(page) {
  const button = page
    .locator(
      '[data-testid="send-button"], #composer-submit-button, button[aria-label*="Send" i], button[aria-label*="发送"]'
    )
    .filter({ visible: true })
    .first();
  await button.waitFor({ state: "visible", timeout: 15000 });
  if (!(await button.isEnabled())) throw new Error("ChatGPT send button is disabled.");
  return button;
}

async function connect(cdpEndpoint) {
  const { chromium } = await loadPlaywright();
  const browser = await chromium.connectOverCDP(cdpEndpoint);
  const context = browser.contexts()[0];
  if (!context) throw new Error("The Edge CDP session has no browser context.");
  return { browser, context };
}

async function doctor(args) {
  const endpoint = args["cdp-endpoint"] ?? "http://127.0.0.1:9222";
  const { context } = await connect(endpoint);
  const page = context.pages().find((item) => item.url().startsWith("https://chatgpt.com")) ??
    (await context.newPage());
  const auth = await authState(page);
  console.log(JSON.stringify({ cdp_ready: true, ...auth }));
}

async function run(args) {
  if (!args["project-dir"]) throw new Error("--project-dir is required.");
  const projectDir = path.resolve(args["project-dir"]);
  const dryRun = args["dry-run"] === "true";
  const validation = await validateProject(projectDir, dryRun);
  if (validation.errors.length) {
    throw new Error(`Preflight failed:\n- ${validation.errors.join("\n- ")}`);
  }
  if (dryRun) {
    console.log(
      JSON.stringify({
        status: "dry_run_ok",
        jobs: validation.jobs.map((job) => ({
          number: job.number,
          prompt: path.relative(projectDir, job.promptPath),
          references: job.referenceFiles.map((file) => path.relative(projectDir, file)),
        })),
      })
    );
    return;
  }

  const endpoint = validation.manifest.cdp_endpoint ?? "http://127.0.0.1:9222";
  const assignmentsPath = path.join(projectDir, "07_browser_jobs", "tab_assignments.json");
  const logPath = path.join(projectDir, "07_browser_jobs", "run_log.jsonl");
  const { context } = await connect(endpoint);
  const pages = [];
  const existing = context.pages().filter((page) => page.url().startsWith("https://chatgpt.com"));

  for (let i = 0; i < 6; i += 1) {
    const page = existing[i] ?? (await context.newPage());
    const auth = await authState(page);
    if (!auth.authenticated) throw new Error(`ChatGPT login was not confirmed in tab ${i + 1}.`);
    pages.push(page);
  }

  const prepared = [];
  for (let i = 0; i < 6; i += 1) {
    const page = pages[i];
    const job = validation.jobs[i];
    try {
      await uploadReferences(page, job.referenceFiles);
      await fillPrompt(page, job.prompt);
      const send = await sendButton(page);
      prepared.push({ page, send, job });
      await appendLog(logPath, {
        event: "job_prepared",
        at: now(),
        job: job.number,
        references: job.referenceFiles.map((file) => path.relative(projectDir, file)),
      });
    } catch (error) {
      await appendLog(logPath, {
        event: "pre_submission_failure",
        at: now(),
        job: job.number,
        error: error.message,
      });
      throw error;
    }
  }

  const results = await Promise.allSettled(
    prepared.map(async ({ page, send, job }) => {
      await send.click();
      await page.waitForTimeout(1000);
      const result = {
        job: job.number,
        status: "submitted",
        url: page.url(),
        submitted_at: now(),
      };
      await appendLog(logPath, { event: "job_submitted", ...result });
      return result;
    })
  );

  const assignments = results.map((result, index) =>
    result.status === "fulfilled"
      ? result.value
      : {
          job: index + 1,
          status: "submission_failure",
          error: result.reason?.message ?? String(result.reason),
          submitted_at: now(),
        }
  );
  await writeJson(assignmentsPath, { assigned_at: now(), tabs: assignments });
  console.log(JSON.stringify({ status: "submission_complete", tabs: assignments }));
}

async function preflight(args) {
  if (!args["project-dir"]) throw new Error("--project-dir is required.");
  const projectDir = path.resolve(args["project-dir"]);
  const validation = await validateProject(projectDir, false);
  if (validation.errors.length) {
    throw new Error(`Preflight failed:\n- ${validation.errors.join("\n- ")}`);
  }
  console.log(JSON.stringify({ status: "preflight_ok", jobs: validation.jobs.length }));
}

const args = parseArgs(process.argv);
try {
  if (args.command === "doctor") await doctor(args);
  else if (args.command === "preflight") await preflight(args);
  else if (args.command === "run") await run(args);
  else throw new Error("Command must be doctor, preflight, or run.");
  process.exit(0);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
