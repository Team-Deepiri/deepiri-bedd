//! ModelKit-aligned stream topic constants.

pub const MODEL_EVENTS = "model-events";
pub const INFERENCE_EVENTS = "inference-events";
pub const PLATFORM_EVENTS = "platform-events";
pub const AGI_DECISIONS = "agi-decisions";
pub const TRAINING_EVENTS = "training-events";
pub const TRAINING_JOBS = "training-jobs";
pub const DOCUMENT_VECTORIZE = "document.vectorize";
pub const DOCUMENT_TRAINING = "document.training";
pub const DOCUMENT_STRUCTURED = "document.structured";
pub const DOCUMENT_ARTIFACTS = "document.artifacts";
pub const HELOX_TRAINING_RAW = "pipeline.helox-training.raw";
pub const HELOX_TRAINING_STRUCTURED = "pipeline.helox-training.structured";
pub const PIPELINE_PRESSURE_EVENTS = "pipeline.pressure.events";
pub const PIPELINE_ARTIFACT_INVALIDATION = "pipeline.artifact.invalidation";
pub const PIPELINE_SPLICE_EVENTS = "pipeline.splice.events";
pub const PIPELINE_DEAD_LETTER = "pipeline.dead-letter";
pub const PIPELINE_METRICS = "pipeline.metrics";

pub const all_document = [_][]const u8{
    DOCUMENT_VECTORIZE,
    DOCUMENT_TRAINING,
    DOCUMENT_STRUCTURED,
    DOCUMENT_ARTIFACTS,
};

test "document topics match ModelKit names" {
    const std = @import("std");
    try std.testing.expectEqualStrings("document.artifacts", DOCUMENT_ARTIFACTS);
    try std.testing.expectEqualStrings("inference-events", INFERENCE_EVENTS);
}
