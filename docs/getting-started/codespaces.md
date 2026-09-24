# Start in GitHub Codespaces

1. **Fork** the repository on GitHub (top-right **Fork** button). Keep it **public** so Argo CD can
   read it without credentials.
2. In your fork, click **Code → Codespaces → ⋯ → New with options**.
3. Choose:
    * **Branch**: `main` (or the branch your facilitator gave you)
    * **Machine type**: **4-core, 16 GB RAM**. The dev container asks for this minimum; smaller
      machines won't be offered.
4. Click **Create codespace**. VS Code opens in the browser.
5. Open the **Terminal** panel. The first thing you'll see is the log of `.devcontainer/bootstrap.sh`.
   Wait for:

    ```text
    === Bootstrap complete - Argo CD is now deploying the TRE (allow 5-10 minutes) ===
    ```

    If you closed it, the full log is in `/tmp/kid-bootstrap.log`.

6. Open the **Ports** tab. Port **80** is labelled *TRE ingress*. Click the globe icon to open it in
   a new browser tab. The URL looks like `https://<codespace-name>-80.app.github.dev/`.

!!! tip "Keep the port private"
    Leave the port's visibility as **Private**. GitHub then only lets *you* reach it, which suits a
    TRE. Private ports need your GitHub login cookie, so open the links from the same browser.

!!! note "Stopping and resuming"
    Codespaces stop after 30 minutes of inactivity by default. When you resume, the k3s container
    restarts on its own and the cluster comes back with its data (it lives in a Docker volume).
    Give it a couple of minutes, then run `tre status`.

    If you **rebuild** the container, the bootstrap runs again. That's safe.

## Costs

A 4-core codespace uses 4 core-hours of your monthly allowance per hour. Delete the codespace
after the workshop (**github.com/codespaces → ⋯ → Delete**) so it doesn't use up storage.

Next: [First steps](first-steps.md).
