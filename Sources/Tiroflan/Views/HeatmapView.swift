import SwiftUI

/// Grille d'activité façon GitHub : une colonne par semaine, lundi en haut.
struct HeatmapView: View {
    let columns: [[HeatCell]]
    let months: [String]

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3
    private let dayLabels = ["L", "", "M", "", "V", "", ""]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: gap) {
                ForEach(months.indices, id: \.self) { i in
                    Text(months[i])
                        .font(.mono(10))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            .padding(.leading, 26)
            .frame(height: 13, alignment: .leading)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(dayLabels[d]).font(.mono(9)).foregroundStyle(Theme.muted).frame(height: cell)
                    }
                }
                .frame(width: 26, alignment: .leading)

                HStack(spacing: gap) {
                    ForEach(columns.indices, id: \.self) { w in
                        VStack(spacing: gap) {
                            ForEach(columns[w]) { c in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(c.isFuture ? Color.clear : Theme.heat[c.level])
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(c.isToday ? Theme.accent : c.isFuture ? Theme.hairline : Color.clear,
                                                          lineWidth: c.isToday ? 1.5 : 1)
                                    )
                                    .frame(width: cell, height: cell)
                                    .help(c.label)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Spacer()
                Text("moins").font(.mono(10)).foregroundStyle(Theme.muted).padding(.trailing, 3)
                ForEach(Theme.heat.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.heat[i]).frame(width: cell, height: cell)
                }
                Text("plus").font(.mono(10)).foregroundStyle(Theme.muted).padding(.leading, 3)
            }
        }
    }
}
