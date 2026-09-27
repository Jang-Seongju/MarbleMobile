import SwiftUI
import UIKit

/// Live game-message list.
///
/// Each game/chat message is one native table row and therefore one VoiceOver
/// element. New messages are inserted as new rows; existing rows are never
/// rebuilt merely because the log grew.
private final class GameMessageCell: UITableViewCell {
    static let reuseIdentifier = "GameMessageCell"

    private let messageLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])

        // Treat one message as one VoiceOver item. The visible label remains the
        // source text, but the cell owns the accessibility element so wrapped
        // visual lines never fragment one logical message.
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        messageLabel.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageLabel.text = nil
        contentView.backgroundColor = .clear
        accessibilityLabel = nil
    }

    func configure(message: GameRoomMessage) {
        messageLabel.text = message.text
        accessibilityLabel = message.text

        switch message.kind {
        case .standard:
            messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
            messageLabel.textColor = .label
            contentView.backgroundColor = .clear

        case .chat:
            // Chat should stand out immediately for low-vision users without
            // changing the spoken/message text itself.
            messageLabel.font = UIFont.preferredFont(forTextStyle: .headline)
            messageLabel.textColor = .black
            contentView.backgroundColor = .systemYellow
        }
    }

    func configurePlaceholder() {
        messageLabel.text = "게임 메시지가 없습니다."
        messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        contentView.backgroundColor = .clear
        accessibilityLabel = "게임 메시지가 없습니다."
    }
}

struct GameMessageLogView: UIViewRepresentable {
    let messages: [GameRoomMessage]

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var messages: [GameRoomMessage] = []

        func numberOfSections(in tableView: UITableView) -> Int {
            1
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            max(messages.count, 1)
        }

        func tableView(
            _ tableView: UITableView,
            cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: GameMessageCell.reuseIdentifier,
                for: indexPath
            ) as? GameMessageCell else {
                return UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            if messages.isEmpty {
                cell.configurePlaceholder()
            } else {
                cell.configure(message: messages[indexPath.row])
            }
            return cell
        }

        func tableView(
            _ tableView: UITableView,
            shouldHighlightRowAt indexPath: IndexPath
        ) -> Bool {
            false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.register(GameMessageCell.self, forCellReuseIdentifier: GameMessageCell.reuseIdentifier)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.allowsSelection = false
        tableView.alwaysBounceVertical = false
        tableView.showsVerticalScrollIndicator = true
        tableView.accessibilityContainerType = .list

        context.coordinator.messages = messages
        tableView.reloadData()
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.messages
        guard previous != messages else { return }

        // Placeholder transitions and any real replacement/reset are document
        // changes, not appends. Reloading is appropriate for those rare cases.
        guard !previous.isEmpty,
              !messages.isEmpty,
              messages.count >= previous.count,
              messages.starts(with: previous) else {
            coordinator.messages = messages
            tableView.reloadData()
            return
        }

        let newCount = messages.count - previous.count
        guard newCount > 0 else { return }

        let insertedRows = (previous.count..<messages.count).map {
            IndexPath(row: $0, section: 0)
        }

        // Update the data source first, then insert only the new rows. Existing
        // visible rows, VoiceOver elements, scroll position, and focus stay intact.
        coordinator.messages = messages
        tableView.performBatchUpdates {
            tableView.insertRows(at: insertedRows, with: .none)
        }
    }
}
