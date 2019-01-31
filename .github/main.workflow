workflow "Deploy to GitHub Pages" {
  on = "push"
  resolves = ["hugo-deploy-gh-pages"]
}

action "hugo-deploy-gh-pages" {
  uses = "joshuarubin/hugo-deploy-gh-pages@master"
  secrets = [
    "GIT_DEPLOY_KEY",
  ]
  env = {
    BRANCH = "gh-pages"
  }
}
