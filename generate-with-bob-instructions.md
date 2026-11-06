## Instructions:

Step 0: Plug in ethernet to Rover router (OL_DEMO). Connect wireless connection to wi-fi.

Step 1 (optional, needed only to generate new tricks in the browser): configure BOB_API_KEY
```bash
cp services/.env.example services/.env
# edit services/.env -> BOB_API_KEY=<your key from https://bob.ibm.com, API Keys section> | Use Inference as API Key scope.
```
Without this file the stack still starts and existing tricks still run.

Step 2: Build images and start (requires internet for the first build)
```bash
cd services
podman-compose -f docker-compose.yml -f docker-compose.freeroam.yml up -d --build
```

Step 3: Stop
```bash
cd services
podman-compose -f docker-compose.yml -f docker-compose.freeroam.yml down
```

Step 4: Navigate to http://localhost:3000, choose Free Roam, and generate commands with Bob in the UI.
