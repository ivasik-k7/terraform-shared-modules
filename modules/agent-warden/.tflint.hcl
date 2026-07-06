# pins tflint's terraform ruleset behavior so local runs and CI agree
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
