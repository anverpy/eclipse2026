# EventBridge Scheduler — bounded to the two days that matter (2026-08-11 dry
# run, 2026-08-12 event), same 18:30-21:30 local (16:30-19:30 UTC, Spain is
# CEST/UTC+2 in August) window both days, nothing fires outside those windows.
#
# Two tiers for the "hero" sources (ree, dgt_traffic, dgt_camera, aggregator):
# a baseline rate across the full window, plus a tighter rate layered on top
# just during totality (20:15-20:45 local / 18:15-18:45 UTC) — see README
# source #5 and CHANGELOG for the cadence discussion. rate() floors at 1
# minute (Scheduler limitation), so the tight tier itself is still 1min —
# dgt_camera and aggregator close the gap to README's original 10-15s
# aspiration by ticking internally a few times per invocation when
# `tier == "tight"` (see their handler.py), independently bounded by the
# Lambda's own timeout. ree/dgt_traffic/aemet/trends don't tick internally:
# their source data doesn't resolve any finer than what's already scheduled
# here, so looping faster would just be redundant requests for no new data
# (a real concern for REE specifically — see README source #1's usage terms).
locals {
  schedules = {
    "ree-dryrun-normal" = { source = "ree", tier = "normal", expr = "rate(5 minutes)", start = "2026-08-11T16:30:00Z", end = "2026-08-11T19:30:00Z" }
    "ree-dryrun-tight"  = { source = "ree", tier = "tight", expr = "rate(2 minutes)", start = "2026-08-11T18:15:00Z", end = "2026-08-11T18:45:00Z" }
    "ree-event-normal"  = { source = "ree", tier = "normal", expr = "rate(5 minutes)", start = "2026-08-12T16:30:00Z", end = "2026-08-12T19:30:00Z" }
    "ree-event-tight"   = { source = "ree", tier = "tight", expr = "rate(2 minutes)", start = "2026-08-12T18:15:00Z", end = "2026-08-12T18:45:00Z" }

    "dgt_traffic-dryrun-normal" = { source = "dgt_traffic", tier = "normal", expr = "rate(5 minutes)", start = "2026-08-11T16:30:00Z", end = "2026-08-11T19:30:00Z" }
    "dgt_traffic-dryrun-tight"  = { source = "dgt_traffic", tier = "tight", expr = "rate(2 minutes)", start = "2026-08-11T18:15:00Z", end = "2026-08-11T18:45:00Z" }
    "dgt_traffic-event-normal"  = { source = "dgt_traffic", tier = "normal", expr = "rate(5 minutes)", start = "2026-08-12T16:30:00Z", end = "2026-08-12T19:30:00Z" }
    "dgt_traffic-event-tight"   = { source = "dgt_traffic", tier = "tight", expr = "rate(2 minutes)", start = "2026-08-12T18:15:00Z", end = "2026-08-12T18:45:00Z" }

    "dgt_camera-dryrun-normal" = { source = "dgt_camera", tier = "normal", expr = "rate(2 minutes)", start = "2026-08-11T16:30:00Z", end = "2026-08-11T19:30:00Z" }
    "dgt_camera-dryrun-tight"  = { source = "dgt_camera", tier = "tight", expr = "rate(1 minute)", start = "2026-08-11T18:15:00Z", end = "2026-08-11T18:45:00Z" }
    "dgt_camera-event-normal"  = { source = "dgt_camera", tier = "normal", expr = "rate(2 minutes)", start = "2026-08-12T16:30:00Z", end = "2026-08-12T19:30:00Z" }
    "dgt_camera-event-tight"   = { source = "dgt_camera", tier = "tight", expr = "rate(1 minute)", start = "2026-08-12T18:15:00Z", end = "2026-08-12T18:45:00Z" }

    # aemet: flat 10min (user call, see CHANGELOG) — hourly station resolution, no benefit to tightening
    "aemet-dryrun" = { source = "aemet", tier = "normal", expr = "rate(10 minutes)", start = "2026-08-11T16:30:00Z", end = "2026-08-11T19:30:00Z" }
    "aemet-event"  = { source = "aemet", tier = "normal", expr = "rate(10 minutes)", start = "2026-08-12T16:30:00Z", end = "2026-08-12T19:30:00Z" }

    # trends: flat 20min — respects Google's own ~8min bucket size and its best-effort/low-priority status
    "trends-dryrun" = { source = "trends", tier = "normal", expr = "rate(20 minutes)", start = "2026-08-11T16:30:00Z", end = "2026-08-11T19:30:00Z" }
    "trends-event"  = { source = "trends", tier = "normal", expr = "rate(20 minutes)", start = "2026-08-12T16:30:00Z", end = "2026-08-12T19:30:00Z" }

    # aggregator: republishes the public dashboard snapshot. Flat 2min tier
    # for the full window, plus the same 1min tight tier as the other hero
    # sources during totality — its handler ticks internally on "tight" so
    # the public snapshot is actually fresh as often as dgt_camera captures,
    # not sitting up to 2 minutes stale during the one part of the day that matters most.
    "aggregator-dryrun-normal" = { source = "aggregator", tier = "normal", expr = "rate(2 minutes)", start = "2026-08-11T16:30:00Z", end = "2026-08-11T19:30:00Z" }
    "aggregator-dryrun-tight"  = { source = "aggregator", tier = "tight", expr = "rate(1 minute)", start = "2026-08-11T18:15:00Z", end = "2026-08-11T18:45:00Z" }
    "aggregator-event-normal"  = { source = "aggregator", tier = "normal", expr = "rate(2 minutes)", start = "2026-08-12T16:30:00Z", end = "2026-08-12T19:30:00Z" }
    "aggregator-event-tight"   = { source = "aggregator", tier = "tight", expr = "rate(1 minute)", start = "2026-08-12T18:15:00Z", end = "2026-08-12T18:45:00Z" }
  }

  poller_arns = {
    ree         = aws_lambda_function.ree_poller.arn
    aemet       = aws_lambda_function.aemet_poller.arn
    dgt_traffic = aws_lambda_function.dgt_traffic_poller.arn
    dgt_camera  = aws_lambda_function.dgt_camera_poller.arn
    trends      = aws_lambda_function.trends_poller.arn
    aggregator  = aws_lambda_function.aggregator.arn
  }
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    sid       = "InvokePollers"
    actions   = ["lambda:InvokeFunction"]
    resources = [for arn in local.poller_arns : arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "${var.project}-scheduler-invoke-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_scheduler_schedule" "poller" {
  for_each = local.schedules

  name       = "${var.project}-${each.key}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = each.value.expr
  start_date          = each.value.start
  end_date            = each.value.end

  target {
    arn      = local.poller_arns[each.value.source]
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      source = "eventbridge-scheduler"
      mode   = "scheduled"
      tier   = each.value.tier
    })
  }
}
