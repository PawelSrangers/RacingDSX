# 1Password secret references. Contains NO real values — safe to commit.
# Resolve at runtime:
#   op run --env-file=config/secrets.env.tpl -- <command>
#   op inject -i config/secrets.env.tpl -o config/secrets.env

SECRET_PLACEHOLDER="op://<vault>/<item>/<field>"
