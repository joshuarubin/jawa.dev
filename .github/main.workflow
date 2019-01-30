workflow "Deploy to GitHub Pages" {
  on = "push"
  resolves = ["hugo-deploy-gh-pages"]
}

action "hugo-deploy-gh-pages" {
  uses = "joshuarubin/hugo-deploy-gh-pages@master"
  secrets = [
    "GITHUB_TOKEN",
    "PAGES_PUSH_ACCESS_TOKEN",
  ]
  env = {
    BRANCH = "gh-pages"
    PAGES_PUSH_USERNAME = "joshuarubin"
  }
}
