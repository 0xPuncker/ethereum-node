resource "google_compute_health_check" "this" {
  name    = "${var.name_prefix}-health-check"
  project = var.project_id

  http_health_check {
    port = var.health_check_port
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

resource "google_compute_backend_service" "this" {
  name                  = "${var.name_prefix}-backend"
  project               = var.project_id
  protocol              = var.backend_protocol
  port_name             = "http"
  timeout_sec           = 30
  enable_cdn            = false
  health_checks         = [google_compute_health_check.this.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = var.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "this" {
  name            = "${var.name_prefix}-url-map"
  project         = var.project_id
  default_service = google_compute_backend_service.this.id
}

resource "google_compute_target_http_proxy" "this" {
  name    = "${var.name_prefix}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.this.id
}

resource "google_compute_global_forwarding_rule" "this" {
  name                  = "${var.name_prefix}-forwarding-rule"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.this.id
}

resource "google_compute_global_address" "this" {
  name    = "${var.name_prefix}-ip"
  project = var.project_id
}
