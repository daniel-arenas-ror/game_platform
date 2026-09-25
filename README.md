docker-compose up -d

run the app 

bin/dev

## Update PROD 

export AWS_PROFILE=mac1-game
git commit -am "add new game"
script/aws_deploy.sh

The script builds the image and pushes it to ECR, tagged with your current commit's short SHA. It then tells the server to pull that image and restart the app. The restart takes a few seconds, so any games in progress will disconnect.

Committing first matters because the tag comes from the commit. If you deploy uncommitted changes, they go out under the previous commit's tag. That makes rollbacks confusing.

A new game also needs its Game record in the database. Don't re-run db:seed on production. db/seeds.rb starts with Game.destroy_all, so every game gets a new ID and any existing rooms break. Instead, create only the new record after deploying:

script/aws_run.sh "/opt/game_platform/bin/rails runner \"Game.find_or_create_by!(code: 'impostor') { |g| g.name = 'Impostor'; g.description = '...' }\""

If the new game has its own seed data, like questions, create that the same way. For more than a line or two, put it in a small rake task and run bin/rails your:task.

Rolling back to an earlier version:

script/aws_run.sh "/opt/game_platform/bin/deploy <old-sha>"

ECR keeps the last 10 images.

## Check Log on deploy ##

- Quick check from your Mac, without logging in:
script/aws_run.sh "cd /opt/game_platform && docker compose ps && docker compose logs --tail 100 web"
- Live logs: open a shell on the server with $(terraform -chdir=terraform output -raw shell_command), then run:
cd /opt/game_platform && sudo docker compose logs -f web caddy
