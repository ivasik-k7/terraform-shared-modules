terraform {
  # 1.5 floor kept for backward compatibility. moved blocks (>=1.1) and resource
  # preconditions (>=1.2) used below are well within that.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # tagPatternList lifecycle rules + enhanced registry scanning need a recent
      # v5 provider; capped under 6 so a major bump can't surprise us. (~> 5.0
      # previously; this only raises the floor, still v5.)
      version = ">= 5.30.0, < 6.0.0"
    }
  }
}
