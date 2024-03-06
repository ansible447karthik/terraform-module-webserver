output "alb_dns_name" {
 value = aws_lb.webserver-lb.dns_name
 description = "The domain name of the webserver LB"
}

output "webserver-lc-sg-id" {
 value = aws_security_group.webserver-lc-sg.id
 description = " the id of the security group of the webserver vm"
}