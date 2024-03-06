locals {
 http_port = 80
 ssh_port = 22
 any_port = 0
 any_protocol = -1
 icmp_all = -1
 icmp_protocol = "icmp"
 tcp_protocol = "tcp"
 all_ips = ["0.0.0.0/0"]
 all_ips_v6 = ["::/0"]
}

# Reference: https://www.terraform.io/language/data-sources
data "aws_vpc" "default-vpc" {
 default = true
}
data "aws_subnets" "default-subnets" {
 filter {
 name = "vpc-id"
 values = [data.aws_vpc.default-vpc.id]
 }
}
data "terraform_remote_state" "db" {
 backend = "s3"
 config = {
 bucket = var.db_remote_state_bucket
 key = var.db_remote_state_key
 region = var.region
 }
}
# API Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_configuration
resource "aws_launch_template" "webserver-lc" {
 name = "${var.cluster_name}-lc"
 image_id = var.ami
 instance_type = var.instance_type
   key_name = "mylocalmumbai"
vpc_security_group_ids = [aws_security_group.webserver-lc-sg.id]
user_data = base64encode(templatefile("${path.module}/user-data.sh", {
  db_address = data.terraform_remote_state.db.outputs.address
  db_port    = data.terraform_remote_state.db.outputs.port
}))
 lifecycle {
 create_before_destroy = true
 }
}
resource "aws_security_group" "webserver-lc-sg" {
 name = "${var.cluster_name}-lc-sg"
 ingress {
 from_port = local.http_port
 to_port = local.http_port
 protocol = local.tcp_protocol
 cidr_blocks = var.ingress_source_cidr
 }
 ingress {
 from_port = local.ssh_port
 to_port = local.ssh_port
 protocol = local.tcp_protocol
 cidr_blocks = var.ingress_source_cidr
 }
 ingress {
 from_port = local.icmp_all
 to_port = local.icmp_all
 protocol = local.icmp_protocol
 cidr_blocks = var.ingress_source_cidr
 }
 egress {
 from_port = 0
 to_port = 0
 protocol = "-1"
 cidr_blocks = ["0.0.0.0/0"]
 ipv6_cidr_blocks = ["::/0"]
 }
}

resource "aws_security_group_rule" "allow_tcp8081_inbound" {
 from_port         = 8081
 protocol          = "tcp"
 security_group_id = aws_security_group.webserver-lc-sg.id
 to_port           = 8081
 type              = "ingress"
 cidr_blocks = local.all_ips
 ipv6_cidr_blocks = local.all_ips_v6
}
# API Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
resource "aws_autoscaling_group" "webserver-asg" {
 launch_template {
    name = aws_launch_template.webserver-lc.name
  }
 #launch_configuration = aws_launch_configuration.webserver-lc.name
 vpc_zone_identifier = data.aws_subnets.default-subnets.ids
 target_group_arns = [aws_lb_target_group.webserver-lb-tg.id]
 health_check_type = "ELB"
 min_size = var.min_server_count
 max_size = var.max_server_count
 tag {
 key = "Name"
 propagate_at_launch = true
 value = "${var.cluster_name}"
 }
}
# Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "webserver-lb" {
 name = "${var.cluster_name}-lb"
 load_balancer_type = "application"
 subnets = data.aws_subnets.default-subnets.ids
 security_groups = [aws_security_group.alb-sg.id]
}
resource "aws_lb_listener" "listener-http" {
 load_balancer_arn = aws_lb.webserver-lb.arn
 port = 80
 default_action {
 type = "fixed-response"
   fixed_response {
 content_type = "text/plain"
 message_body = "404: page not found"
 status_code = 404
 }
 }
}
# Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule
resource "aws_lb_listener_rule" "webserver-asg-rule" {
 listener_arn = aws_lb_listener.listener-http.arn
 priority = 100
 condition {
 path_pattern {
 values = ["*"]
 }
 }
 action {
 type = "forward"
 target_group_arn = aws_lb_target_group.webserver-lb-tg.arn
 }
 condition {}
}
resource "aws_security_group" "alb-sg" {
 name = "${var.cluster_name}-alb-sg"
 # Allow ingress HTTP traffic
 ingress {
 from_port = local.http_port
 protocol = local.tcp_protocol
 to_port = local.http_port
 cidr_blocks = local.all_ips
 }
 # Allow all egress traffic
 egress {
 from_port = local.any_port
 protocol = local.any_protocol
 to_port = local.any_port
 cidr_blocks = local.all_ips
 }
}
# Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
resource "aws_lb_target_group" "webserver-lb-tg" {
 name = "${var.cluster_name}-lb-tg"
 port = 80
 protocol = "HTTP"
 vpc_id = data.aws_vpc.default-vpc.id
 health_check {
 path = "/"
 protocol = "HTTP"
 matcher = "200"
 interval = 15
 timeout = 3
 unhealthy_threshold = 2
 healthy_threshold = 2
 }
}
