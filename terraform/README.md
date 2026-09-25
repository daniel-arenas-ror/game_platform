# AWS deployment (Terraform)

One EC2 instance running Docker Compose. That fits the single-process `async` ActionCable adapter.

```
Internet ──443──▶ Caddy (TLS, Let's Encrypt) ──▶ web (Rails/Thruster) ──▶ mongo
                          EC2 (t4g.small, Amazon Linux 2023)
                          /data  ← separate encrypted EBS volume, daily snapshots
```

- **ECR** stores the app image. **SSM Parameter Store** holds `RAILS_MASTER_KEY` and the generated Mongo password.
- **Session Manager** gives you shell access, so port 22 is closed and no SSH key is needed.
- **Elastic IP.** Without a domain, the app is served at `https://<ip-with-dashes>.sslip.io`.

## First deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set acme_email (+ domain_name if you have one)
terraform init
terraform apply                                # reads ../config/master.key

cd ..
script/aws_deploy.sh                           # build → push to ECR → restart on the instance
script/aws_run.sh "/opt/game_platform/bin/rails db:seed"   # once only: seeds.rb destroy_all's Games
terraform -chdir=terraform output app_url
```

Prerequisites: AWS CLI configured, Docker running, and `jq`.

## Day to day

| Task | Command |
|---|---|
| Deploy current commit | `script/aws_deploy.sh` |
| Roll back to a tag | `script/aws_run.sh "/opt/game_platform/bin/deploy <tag>"` |
| Shell on the box | `$(terraform -chdir=terraform output -raw shell_command)` |
| Rails console (in the shell) | `sudo /opt/game_platform/bin/rails console` |
| Logs (in the shell) | `cd /opt/game_platform && sudo docker compose logs -f web` |

## Notes

- A custom domain needs an A record pointing at `public_ip`. Terraform creates it for you when `route53_zone_name` is set. Point it **before** the first deploy so Caddy can issue the cert.
- Changing `files/*` or most instance settings **replaces the instance**. Mongo data and TLS certs live on the `/data` EBS volume and are reattached. The latest image is redeployed automatically on boot.
- `terraform destroy` deletes the data volume too. Snapshots from the backup policy are kept until they expire.
- Deploys restart the `web` container, so there are a few seconds of downtime and connected games will drop.
- Scaling past one instance means switching `config/cable.yml` to Redis and moving to an ALB + ElastiCache/DocumentDB setup.
