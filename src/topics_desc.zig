const topics = @import("topics.zig");

pub const Desc = struct { name: []const u8, purpose: []const u8 };

pub const catalog = [_]Desc{
    .{ .name = topics.DOCUMENT_ARTIFACTS, .purpose = "LIS artifact materialization" },
    .{ .name = topics.DOCUMENT_VECTORIZE, .purpose = "embedding / chunk fanout" },
    .{ .name = topics.DOCUMENT_TRAINING, .purpose = "training pair emission" },
    .{ .name = topics.DOCUMENT_STRUCTURED, .purpose = "structured extraction" },
    .{ .name = topics.INFERENCE_EVENTS, .purpose = "inference plane" },
    .{ .name = topics.PIPELINE_DEAD_LETTER, .purpose = "failed strike DLQ" },
    .{ .name = topics.PIPELINE_METRICS, .purpose = "pipeline metrics" },
    .{ .name = topics.PIPELINE_PRESSURE_EVENTS, .purpose = "AGI pressure signals" },
    .{ .name = topics.PIPELINE_SPLICE_EVENTS, .purpose = "AGI splice events" },
    .{ .name = topics.PIPELINE_ARTIFACT_INVALIDATION, .purpose = "artifact invalidation" },
    .{ .name = topics.HELOX_TRAINING_RAW, .purpose = "Helox raw training samples" },
    .{ .name = topics.HELOX_TRAINING_STRUCTURED, .purpose = "Helox structured training" },
    .{ .name = topics.MODEL_EVENTS, .purpose = "model lifecycle" },
    .{ .name = topics.PLATFORM_EVENTS, .purpose = "platform bus" },
    .{ .name = topics.AGI_DECISIONS, .purpose = "AGI decisions" },
    .{ .name = topics.TRAINING_EVENTS, .purpose = "training events" },
};
