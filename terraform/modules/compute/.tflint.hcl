plugin "google" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-google"
  version = "0.29.0"
}

config {
  # Replaces the old `module = true` (removed in v0.54)
  call_module_type = "all"
  format = "compact" # optional
}

# Useful core rules
rule "terraform_naming_convention" { enabled = true }
rule "terraform_unused_declarations" { enabled = true }
