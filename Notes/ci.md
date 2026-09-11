# Continuous Integration (CI) with GitHub Actions

> **Topic:** What is CI, The Mental Model of Writing CI Workflows (Mirroring Local Terminal), Structure of `.github/workflows/ci.yml`, Ephemeral Service Containers, and Dependency Caching.

---

## 1. What is CI (Continuous Integration)?

In team software engineering, developers work on separate git branches and merge their code into the `main` branch.

### The Real-World Problem: "It Works on My Machine" Syndrome
* A developer writes code on their laptop, runs it, and it works because of some local file, leftover database row, or uncommitted environment variable.
* They push their code to GitHub and merge a Pull Request.
* Immediately, the staging or production server crashes because:
  * An import path was misspelled.
  * A database migration was missing.
  * An npm dependency wasn't listed in `package.json`.
  * An automated test was broken.

### The Solution: An Automated Cloud Gatekeeper
**Continuous Integration (CI)** is an automated system that acts as an unyielding gatekeeper.
* Every time a developer pushes a commit or opens a Pull Request:
* GitHub spins up a **brand-new, completely clean virtual machine** in the cloud.
* It checks out the repository, installs dependencies from scratch, spins up test services, and runs your test and build commands.
* **If even one test fails, GitHub blocks the merge!** Broken code is physically stopped before it ever enters `main`.

---

### Why Run `npm test` in the Cloud If We Already Run It Locally?

A natural question every developer asks is: *"If I already run `npm test` on my laptop before pushing, why do we waste cloud compute running the exact same test on GitHub?"*

Here are the 3 real-world engineering reasons:

#### 1. The "Forgotten File" Trap (The Classic Git Gotcha)
Imagine you write a new feature and create a new utility file: `backend/src/utils/dateFormatter.js`.
* You import it in your controller, run `npm test` on your laptop, and **it passes 100%**.
* Why did it pass? Because the file physically exists on your laptop's hard drive!
* But when committing, you forgot to `git add` that file, or it was accidentally ignored by a rule in `.gitignore`.
* You push your commit to GitHub.
* **Without Cloud CI:** You merge the code into `main`. The production server pulls the code, tries to run it, and immediately crashes for all live users with: `Error: Cannot find module './utils/dateFormatter.js'`.
* **WITH Cloud CI:** GitHub Actions clones **strictly what you pushed to Git**. It runs `npm test` on a machine that has never seen your laptop. It immediately flags: `Cannot find module`, turns red, and **blocks you from merging the broken code!**

#### 2. The "Sterile Environment" Guarantee
Your local laptop is "dirty" with history:
* You might have leftover test records in your local PostgreSQL database.
* You might have packages installed globally on your machine (`npm install -g`) that aren't listed in `package.json`.
* You might have environment variables set in your Windows system settings.
* A GitHub Actions runner is **100% sterile**. It has no history, no global packages, and no extra files. If the test passes in CI, you have mathematical proof that your code is truly self-contained and reproducible.

#### 3. The Windows vs. Linux Case-Sensitivity Trap
* **Windows is case-insensitive:** If a file is named `SeatMap.jsx`, Windows lets you write `import SeatMap from './seatMap.jsx'`. Your local tests will pass!
* **Linux (Production) is strictly case-sensitive:** On a production Linux server, `./seatMap.jsx` will crash with file not found.
* Because GitHub Actions runs on **Linux (`ubuntu-latest`)**, it catches these OS-specific bugs before they reach real customers.

---

## 2. The Mental Model: How to Write a CI Workflow

When writing a CI YAML file (`.github/workflows/ci.yml`), beginners often feel overwhelmed by the syntax. 

### The Secret: Mirroring Your Local Terminal Steps
A GitHub Actions runner (like `ubuntu-latest`) is simply a **clean, blank computer sitting in a GitHub data center**. 

To write a workflow, you simply ask yourself:
> *"If I sat down at a brand-new computer with a fresh terminal, what exact commands would I type to test my project?"*

| What You Do on Your Laptop | What You Tell GitHub Actions in `ci.yml` |
|---|---|
| 1. Clone the repository | `uses: actions/checkout@v4` |
| 2. Install Node.js | `uses: actions/setup-node@v4` with `node-version: 20` |
| 3. Open terminal in `backend/` | `working-directory: backend` |
| 4. Type `npm ci` | `run: npm ci` |
| 5. Start PostgreSQL | `services: postgres: image: postgres:15-alpine` |
| 6. Type `npm test` | `run: npm test` |

If you know how to run your project in your local terminal, you already know how to write a CI pipeline!

---

## 3. Dissecting the Anatomy of `.github/workflows/ci.yml`

Here is how our project's workflow is structured:

```text
               .github/workflows/ci.yml
                          │
         ┌────────────────┴────────────────┐
         ▼                                 ▼
   [ on: push / pull_request ]      [ jobs: ]
   (The Triggers)                   (Parallel Virtual Machines)
                                           │
                       ┌───────────────────┴───────────────────┐
                       ▼                                       ▼
             Job 1: backend-test                     Job 2: frontend-build
             - Spins up Ubuntu VM                    - Spins up Ubuntu VM
             - Starts Ephemeral PostgreSQL           - Runs Oxlint
             - Runs Jest & Migrations                - Runs Vite Build
```

### Key Directives Explained:

* **`on: push: branches: [ main ]`**: The **Event Trigger**. Tells GitHub to wake up and execute this workflow whenever commits are pushed or PRs are opened against `main`.
* **`jobs:`**: Defines the tasks. Each job runs on its own **completely isolated virtual machine in parallel**, saving time.
* **`runs-on: ubuntu-latest`**: Specifies the operating system of the virtual machine provided by GitHub.
* **`uses: actions/...`**: Reusable community or official actions (like pre-built macros for checking out git code or downloading Node.js).
* **`run:`**: Executes standard shell commands in the virtual machine's terminal (e.g. `npm ci`, `npm test`).

---

## 4. Why Do We Spin Up a PostgreSQL Service Container on CI?

Look at lines 18–31 of `.github/workflows/ci.yml`:
```yaml
services:
  postgres:
    image: postgres:15-alpine
    env:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password123
      POSTGRES_DB: movie_booking_test
    ports:
      - 5432:5432
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
```

### The Real-World Reason:
* Our backend tests are **real integration tests** (`booking.concurrency.test.js`, `movies.test.js`, `booking.verify.test.js`). They execute real SQL transactions, test row-level locks (`SELECT FOR UPDATE`), and query tables.
* A fresh GitHub Actions virtual machine does **not** have PostgreSQL installed or running.
* If we ran `npm test` without a database, every database query would fail with `ECONNREFUSED`.

### The Ephemeral Service Container:
* **`services:`** tells GitHub Actions to launch Docker containers alongside the virtual machine.
* GitHub pulls `postgres:15-alpine` and attaches it to the runner on `localhost:5432`.
* **`--health-cmd pg_isready`**: The runner waits until PostgreSQL has completed its internal startup and is ready to accept connections before running `npm test`.
* **Ephemeral Lifecycle:** Once the tests finish, GitHub **instantly destroys the container and the virtual machine**. No data is stored, and no cleanup is needed. Every test run starts from a 100% pristine state.

---

## 5. Dependency Caching (`cache: 'npm'`)

Downloading 200MB of `node_modules` from the internet on every single git push slows down builds and wastes bandwidth.

```yaml
- name: Set up Node.js 20
  uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: 'npm'
    cache-dependency-path: backend/package-lock.json
```

* **How it works:** GitHub computes a cryptographic hash of your `package-lock.json`.
* **The First Run:** Downloads packages from npm registry and saves a snapshot to GitHub's internal cache.
* **Subsequent Runs:** If `package-lock.json` hasn't changed, GitHub restores the cached packages in **2 seconds**, cutting your CI pipeline runtime from minutes down to seconds!

---

## 6. Frontend CI Verification (`frontend-build`)

The second job verifies code quality and compilation integrity for the React client:

```yaml
- name: Run Oxlint linter
  working-directory: frontend
  run: npm run lint

- name: Verify production Vite build compiles cleanly
  working-directory: frontend
  run: npm run build
```

1. **Oxlint Check:** Catches illegal React Hook calls (`react/rules-of-hooks`) or broken exports before human review.
2. **Vite Build Check:** Ensures that JSX compiles cleanly into `dist/` without broken imports, missing assets, or syntax errors. If someone broke a component import, the build fails and flags the commit with a red cross on GitHub!
