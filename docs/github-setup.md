# Pushing to GitHub from GCP VM

## One-time setup on your GCP VM

### Step 1: Configure git identity
```bash
git config --global user.name "Sourav Nandy"
git config --global user.email "nandy.sourav09@gmail.com"
```

### Step 2: Generate SSH key on the GCP VM
```bash
ssh-keygen -t ed25519 -C "nandy.sourav09@gmail.com"
# Press Enter for all prompts (default location, no passphrase)
```

### Step 3: Copy the public key
```bash
cat ~/.ssh/id_ed25519.pub
# Copy the entire output
```

### Step 4: Add to GitHub
1. Go to github.com → Settings → SSH and GPG keys
2. Click "New SSH key"
3. Title: "GCP k8s-control"
4. Paste the public key
5. Click "Add SSH key"

### Step 5: Test connection
```bash
ssh -T git@github.com
# Should say: Hi sourav-ndx! You've successfully authenticated
```

---

## Push this repo to GitHub

```bash
# Clone your existing repo
cd ~
git clone git@github.com:sourav-ndx/k8s-kubeadm-gcp.git
cd k8s-kubeadm-gcp

# Copy all files into the repo
cp -r ~/k8s-repo/setup ./
cp -r ~/k8s-repo/manifests ./
cp -r ~/k8s-repo/docs ./

# Make scripts executable
chmod +x setup/*.sh

# Add, commit, push
git add .
git commit -m "feat: add setup scripts, manifests, and networking docs"
git push origin main
```

---

## Daily workflow after this

```bash
cd ~/k8s-kubeadm-gcp
# make changes
git add .
git commit -m "your message"
git push origin main
```



