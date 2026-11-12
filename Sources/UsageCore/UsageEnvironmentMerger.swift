import Foundation

/// Holds raw source identities only while combining environments on the host.
struct EnvironmentUsage {
  let id: String
  let summary: UsageResponse
}

struct MergedEnvironmentUsage {
  let summary: UsageResponse
  let duplicateSourceCount: Int
  let supplementedPartialSource: Bool
}

enum UsageEnvironmentMergeError: Error, Equatable {
  case empty
  case incompatibleContract
  case differentWindow
  case differentFilter
  case missingSourceIdentity
  case missingBucketIdentity
  case duplicateEnvironment
  case unsupportedSourceStatus
}

/// Mirrors T3's source ownership priority and supplemental partial-scan handling.
enum UsageEnvironmentMerger {
  private struct Owner {
    let environment: EnvironmentUsage
    let source: Source
    let timestamp: Date
  }
  private struct Cell: Hashable {
    let day: String
    let hour: String?
    let provider: String
    let model: String
  }
  private struct BucketReference: Hashable {
    let environment: String
    let index: Int
  }

  static func merge(_ inputs: [EnvironmentUsage]) throws -> MergedEnvironmentUsage {
    guard let first = inputs.first else { throw UsageEnvironmentMergeError.empty }
    let baseline = first.summary
    guard Set(inputs.map(\.id)).count == inputs.count else {
      throw UsageEnvironmentMergeError.duplicateEnvironment
    }
    for input in inputs {
      let summary = input.summary
      guard (4...6).contains(summary.contractVersion) else {
        throw UsageEnvironmentMergeError.incompatibleContract
      }
      guard summary.sinceDay == baseline.sinceDay, summary.untilDay == baseline.untilDay,
        summary.timeZone == baseline.timeZone, summary.sinceTime == baseline.sinceTime,
        summary.untilTime == baseline.untilTime
      else { throw UsageEnvironmentMergeError.differentWindow }
      guard summary.modelFilter == baseline.modelFilter else {
        throw UsageEnvironmentMergeError.differentFilter
      }
      guard summary.readAt.flatMap(UsageDates.parse) != nil else {
        throw UsageEnvironmentMergeError.missingSourceIdentity
      }
      for source in summary.sources {
        guard ["ok", "partial", "failed", "missing"].contains(source.status) else {
          throw UsageEnvironmentMergeError.unsupportedSourceStatus
        }
        if source.status == "missing" { continue }
        guard source.fingerprint != nil, source.distinctSessions != nil else {
          throw UsageEnvironmentMergeError.missingSourceIdentity
        }
      }
      for bucket in summary.buckets {
        guard bucket.day != nil, bucket.model != nil else {
          throw UsageEnvironmentMergeError.missingBucketIdentity
        }
      }
    }
    let ordered = inputs.sorted { left, right in
      let a = left.summary.readAt.flatMap(UsageDates.parse) ?? .distantPast
      let b = right.summary.readAt.flatMap(UsageDates.parse) ?? .distantPast
      return a == b ? left.id < right.id : a > b
    }
    var owners: [SourceFingerprint: Owner] = [:]
    var sessions: [SourceFingerprint: Int] = [:]
    var duplicateCount = 0
    for status in ["ok", "partial", "failed"] {
      for input in ordered {
        for source in input.summary.sources where source.status == status {
          guard let fingerprint = source.fingerprint,
            let timestamp = input.summary.readAt.flatMap(UsageDates.parse)
          else { continue }
          if owners[fingerprint] != nil {
            duplicateCount += 1
            continue
          }
          owners[fingerprint] = Owner(environment: input, source: source, timestamp: timestamp)
          sessions[fingerprint] = source.distinctSessions ?? 0
        }
      }
    }
    var seen: [SourceFingerprint: Set<Cell>] = [:]
    var supplemental = Set<BucketReference>()
    for input in ordered {
      for source in input.summary.sources where source.status == "partial" {
        guard let fingerprint = source.fingerprint, let owner = owners[fingerprint],
          owner.source.status == "ok", let time = input.summary.readAt.flatMap(UsageDates.parse),
          time > owner.timestamp
        else { continue }
        var cells: Set<Cell>
        if let existing = seen[fingerprint] {
          cells = existing
        } else {
          cells = Set(try cellsForSource(owner.environment.summary, fingerprint))
        }
        var added = false
        for (index, bucket) in input.summary.buckets.enumerated()
        where belongs(bucket, to: fingerprint, in: input.summary) {
          let cell = try cell(for: bucket)
          if cells.insert(cell).inserted {
            supplemental.insert(BucketReference(environment: input.id, index: index))
            added = true
          }
        }
        seen[fingerprint] = cells
        if added {
          sessions[fingerprint] = max(sessions[fingerprint] ?? 0, source.distinctSessions ?? 0)
        }
      }
    }
    var mergedBuckets: [Bucket] = []
    for input in inputs {
      let owned = owners.filter { $0.value.environment.id == input.id }.map(\.key)
      for (index, bucket) in input.summary.buckets.enumerated() {
        let isSupplement = supplemental.contains(
          BucketReference(environment: input.id, index: index))
        let isOwned = owned.contains { fingerprint in
          fingerprint.provider == bucket.provider
            && (bucket.sourcePath == nil || bucket.sourcePath == fingerprint.resolvedHomePath)
        }
        if isSupplement || isOwned { mergedBuckets.append(bucket) }
      }
    }
    let mergedSources = owners.map { fingerprint, owner in
      Source(
        status: owner.source.status, fingerprint: fingerprint,
        distinctSessions: sessions[fingerprint])
    }
    let unavailable = inputs.contains { $0.summary.pricing.status == "unavailable" }
    let merged = UsageResponse(
      contractVersion: baseline.contractVersion, readAt: baseline.readAt,
      sinceDay: baseline.sinceDay, untilDay: baseline.untilDay, timeZone: baseline.timeZone,
      sinceTime: baseline.sinceTime, untilTime: baseline.untilTime,
      modelFilter: baseline.modelFilter,
      buckets: mergedBuckets, sources: mergedSources,
      pricing: Pricing(status: unavailable ? "unavailable" : "cached"))
    return MergedEnvironmentUsage(
      summary: merged, duplicateSourceCount: duplicateCount,
      supplementedPartialSource: !supplemental.isEmpty)
  }

  private static func cell(for bucket: Bucket) throws -> Cell {
    guard let day = bucket.day, let model = bucket.model else {
      throw UsageEnvironmentMergeError.missingBucketIdentity
    }
    return Cell(day: day, hour: bucket.hourStart, provider: bucket.provider, model: model)
  }

  private static func cellsForSource(_ summary: UsageResponse, _ fingerprint: SourceFingerprint)
    throws -> [Cell]
  {
    try summary.buckets.filter { belongs($0, to: fingerprint, in: summary) }.map {
      try cell(for: $0)
    }
  }

  private static func belongs(
    _ bucket: Bucket, to source: SourceFingerprint, in summary: UsageResponse
  ) -> Bool {
    let count = summary.sources.filter { $0.fingerprint?.provider == source.provider }.count
    return bucket.provider == source.provider
      && (bucket.sourcePath == source.resolvedHomePath || (bucket.sourcePath == nil && count == 1))
  }
}
