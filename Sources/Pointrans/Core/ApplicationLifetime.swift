@MainActor
final class ApplicationLifetime<Delegate: AnyObject> {
    let delegate: Delegate

    init(delegate: Delegate) {
        self.delegate = delegate
    }
}
