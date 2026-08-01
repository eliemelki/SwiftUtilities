final class DropdownButton: UIControl {

    private let titleLabel = UILabel()
    private let chevronView = UIImageView(
        image: UIImage(systemName: "chevron.down")
    )

    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor

        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textAlignment = .left

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        chevronView.tintColor = .secondaryLabel
        chevronView.contentMode = .scaleAspectFit

        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(chevronView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 12
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronView.leadingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            chevronView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -12
            ),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),

            heightAnchor.constraint(equalToConstant: 40)
        ])
    }
}
