Okay, let's set up Option 3: Git push from your Mac triggers a build and deploy directly on your Proxmox VM. This gives you a nice automated workflow without needing external services.

**Overview:**

1.  **VM Setup:** Install Git & Docker, create a dedicated user, set up a bare Git repository, create a checkout/build directory, and write the `post-receive` hook script.
2.  **Mac Setup:** Configure SSH access to the VM for the deployment user, add the VM's Git repo as a remote to your local project.
3.  **Workflow:** Write code -> `git commit` -> `git push deploy main` -> VM receives push -> hook script runs -> Docker builds -> container restarts.

---

**Phase 1: Proxmox VM Setup**

*Assume you have a Debian/Ubuntu based VM running on Proxmox with a static IP (replace `vm-ip` with the actual IP).*

1.  **Install Prerequisites:**
    ```bash
    sudo apt update
    sudo apt install -y git docker.io # Or follow official Docker install guide
    ```

2.  **Create Deployment User:** (Recommended, avoids running everything as root or your personal user)
    ```bash
    sudo adduser deployer
    # Follow prompts to set password, etc.
    ```

3.  **Add User to Docker Group:** (Allows `deployer` to run Docker commands without `sudo`)
    ```bash
    sudo usermod -aG docker deployer
    # IMPORTANT: The deployer user needs to log out and log back in,
    # OR you can use `su - deployer` in a new session for this to take effect
    # when testing later. The hook script environment might inherit groups correctly.
    ```

4.  **Create Bare Git Repository:** (This holds the Git history, no working files)
    ```bash
    # As root or using sudo
    sudo mkdir -p /opt/git/my-spotify-app.git
    sudo chown deployer:deployer /opt/git/my-spotify-app.git
    cd /opt/git/my-spotify-app.git
    sudo -u deployer git init --bare
    echo "Bare Git repository created at /opt/git/my-spotify-app.git"
    ```
    *Output should confirm initialization.*

5.  **Create Checkout/Build Directory:** (Where the hook will temporarily place files for building)
    ```bash
    # As root or using sudo
    sudo mkdir -p /opt/apps/my-spotify-app-build
    sudo chown deployer:deployer /opt/apps/my-spotify-app-build
    echo "Build directory created at /opt/apps/my-spotify-app-build"
    ```

6.  **Create the `post-receive` Git Hook:**
    *   This script runs automatically *on the VM* after a successful `git push` to the bare repo.
    *   Edit the file (use `sudo vim`, `sudo nano`, etc.):
        ```bash
        sudo nano /opt/git/my-spotify-app.git/hooks/post-receive
        ```
    *   Paste the following script content:

        ```bash
        #!/bin/bash
        # === Git Post-Receive Hook for Docker Deployment ===

        # Exit immediately if a command exits with a non-zero status.
        set -e

        # --- Configuration ---
        GIT_DIR="/opt/git/my-spotify-app.git"       # Path to the bare Git repository
        TARGET_DIR="/opt/apps/my-spotify-app-build" # Temp directory to checkout code for building
        IMAGE_BASENAME="local/my-spotify-app"       # Base name for the Docker image
        CONTAINER_NAME="my-spotify-app"             # Name for the running container
        DEPLOY_BRANCH="main"                        # Branch to deploy (change if using 'master' etc.)
        CONTAINER_PORT_MAPPING="8080:8080"          # HostPort:ContainerPort (adjust if your app uses a different internal port)
        # Optional: Define path to offline data ON THE VM if mounting a volume
        # OFFLINE_DATA_PATH_VM="/path/on/vm/to/spotify-data"
        # CONTAINER_DATA_PATH="/app/data" # Path inside the container

        # --- Script Logic ---
        echo "----------------------------------------------------"
        echo "Git Hook: Received push. Starting deployment process..."
        echo "----------------------------------------------------"

        # Read stdin to get branch info (format: <oldrev> <newrev> <refname>)
        while read oldrev newrev refname; do
          BRANCH=$(git rev-parse --symbolic --abbrev-ref $refname)

          if [[ "$BRANCH" == "$DEPLOY_BRANCH" ]]; then
            echo "Detected push to deploy branch: $BRANCH"

            # Get the short commit hash for tagging
            COMMIT_HASH=$(git --git-dir="$GIT_DIR" rev-parse --short $newrev)
            IMAGE_TAG="${IMAGE_BASENAME}:${COMMIT_HASH}"
            LATEST_TAG="${IMAGE_BASENAME}:latest"

            echo "----> Checking out commit $COMMIT_HASH to $TARGET_DIR..."
            # Use the deployer user to checkout (ensure permissions)
            # Force checkout to overwrite previous build files
            git --work-tree="$TARGET_DIR" --git-dir="$GIT_DIR" checkout $DEPLOY_BRANCH -f

            echo "----> Building Docker image: $IMAGE_TAG (and $LATEST_TAG)"
            # Build context is the checkout directory
            cd "$TARGET_DIR"
            # Run docker build AS the deployer user
            docker build -t "$IMAGE_TAG" .
            docker tag "$IMAGE_TAG" "$LATEST_TAG"
            cd ~ # Go back to home dir or somewhere safe

            echo "----> Deployment: Stopping and removing old container '$CONTAINER_NAME'..."
            # Use deployer user for docker commands. Ignore errors if container doesn't exist.
            docker stop "$CONTAINER_NAME" || true
            docker rm "$CONTAINER_NAME" || true

            echo "----> Deployment: Starting new container '$CONTAINER_NAME' from image '$IMAGE_TAG'..."
            # Add any necessary runtime environment variables with -e
            # Add volume mounts with -v if needed (e.g., for offline data)
            docker run -d \
              --name "$CONTAINER_NAME" \
              -p "$CONTAINER_PORT_MAPPING" \
              --restart unless-stopped \
              # Example: Mount offline data from VM into container
              # -v "${OFFLINE_DATA_PATH_VM}:${CONTAINER_DATA_PATH}" \
              # Example: Pass an environment variable
              # -e "MY_VARIABLE=some_value" \
              "$IMAGE_TAG"

            echo "----------------------------------------------------"
            echo "Deployment of commit $COMMIT_HASH completed successfully."
            echo "Access at: http://$(hostname -I | awk '{print $1'}):${CONTAINER_PORT_MAPPING%%:*}" # Prints VM IP and host port
            echo "----------------------------------------------------"

          else
            echo "Push detected for branch '$BRANCH', but deployment only configured for '$DEPLOY_BRANCH'. Skipping build/deploy."
          fi
        done

        exit 0
        ```

7.  **Make the Hook Executable:**
    ```bash
    sudo chmod +x /opt/git/my-spotify-app.git/hooks/post-receive
    ```

8.  **Ensure Correct Ownership (Crucial!):** The hook script will likely run as the user pushing the code (`deployer` in our case). Ensure this user owns the necessary directories and the hook itself.
    ```bash
    sudo chown deployer:deployer /opt/git/my-spotify-app.git/hooks/post-receive
    sudo chown -R deployer:deployer /opt/apps/my-spotify-app-build
    # Git repo ownership was set earlier
    ```

---

**Phase 2: Mac Setup**

1.  **SSH Key Authentication (Highly Recommended):**
    *   **Check for existing key:** `ls ~/.ssh/id_rsa.pub`
    *   **Generate if needed:** `ssh-keygen -t rsa -b 4096` (follow prompts, pressing Enter for defaults is usually fine)
    *   **Copy Public Key to VM:**
        ```bash
        # Replace deployer@vm-ip with your actual details
        ssh-copy-id deployer@vm-ip
        ```
        *Enter the `deployer` user's password when prompted.*
    *   **Test SSH login:**
        ```bash
        ssh deployer@vm-ip
        # Should log you in without a password prompt. Type 'exit' to leave.
        ```

2.  **Add VM Git Repo as Remote:**
    *   Navigate to your project directory on your Mac in the Terminal:
        ```bash
        cd /path/to/your/spotify-app-project
        ```
    *   Add the remote (give it a name like `deploy` or `vm`):
        ```bash
        # Replace deployer@vm-ip with your actual details
        git remote add deploy deployer@vm-ip:/opt/git/my-spotify-app.git
        ```
    *   Verify the remote was added:
        ```bash
        git remote -v
        # Should show 'deploy' pointing to the VM path for fetch and push
        ```

---

**Phase 3: Development and Deployment Workflow**

1.  **Develop:** Make changes to your application code and/or `Dockerfile` on your Mac within your project directory.
2.  **Commit:** Stage and commit your changes using Git:
    ```bash
    git add .
    git commit -m "feat: Add new chart feature"
    ```
3.  **Deploy:** Push your changes *to the deploy remote* (this triggers the hook on the VM):
    ```bash
    # Assuming your local branch is 'main' and the hook expects 'main'
    git push deploy main
    ```
4.  **Monitor Output:** Watch the terminal output from the `git push` command. You will see the `echo` statements from the `post-receive` hook script on the VM, showing the build progress and deployment steps. Any errors during build or deploy will appear here.
5.  **Verify:** Once the push completes successfully, open a web browser on your Mac (or any device on your home network) and navigate to `http://vm-ip:8080` (using the VM's IP and the host port mapped in the hook script, e.g., 8080). You should see your updated application.

---

**Important Considerations:**

*   **Dockerfile:** Ensure your `Dockerfile` is correct and located in the root of your Git repository. If it needs access to the offline Spotify data *during the build*, use `COPY` instructions within the Dockerfile.
*   **Offline Data Runtime Access:** If your *running application* needs access to the offline data, and it's too large to copy into the image, make sure the data exists somewhere on the VM (e.g., `/data/spotify`) and uncomment/adjust the `-v` volume mount line in the `post-receive` hook script:
    `-v "/data/spotify:/app/data"` (Map VM path `/data/spotify` to `/app/data` inside the container). Ensure the `deployer` user has read access to the data on the VM.
*   **Environment Variables/Secrets:** If your application needs API keys or other secrets *at runtime*, pass them securely using the `-e` flag in the `docker run` command within the `post-receive` hook. **Do not commit secrets directly into your Git repository.**
*   **Error Handling:** If a `git push` fails, check the output carefully. If the hook script fails mid-way:
    *   SSH into the VM: `ssh deployer@vm-ip`
    *   Check Docker logs: `docker logs my-spotify-app` (if the container started briefly)
    *   Check Docker status: `docker ps -a`
    *   Manually inspect the build directory: `ls -la /opt/apps/my-spotify-app-build`
    *   Review the hook script logic.
*   **Permissions:** Incorrect file ownership or Docker group membership for the `deployer` user is the most common cause of hook failures. Double-check ownership of `/opt/git/my-spotify-app.git`, `/opt/apps/my-spotify-app-build`, and the hook script itself.