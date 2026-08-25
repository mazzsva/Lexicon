//
//  EntryCardView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import SwiftUI

struct EntryCardView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.term)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !entry.definition.isEmpty {
                    Text(entry.definition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.bookmark)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(Entry.mocks) { entry in
            EntryCardView(entry: entry)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .groupedBackground()
}
