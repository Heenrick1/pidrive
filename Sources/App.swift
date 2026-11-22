import UIKit
import UserNotifications

let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
let fmt: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateStyle = .full; return f }()
let timeFmt: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()
extension Notification.Name { static let synced = Notification.Name("synced") }
func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? s }

struct Reminder: Codable { var id: String; var title: String; var notes: String; var time: String; var file: String
    var date: Date { iso.date(from: time) ?? Date() } }
struct RFile: Codable { var name: String; var size: Int }

enum API {
    static var base: String { (UserDefaults.standard.string(forKey: "url") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
    static func req(_ path: String, _ method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard let u = URL(string: base + path) else { return nil }
        var r = URLRequest(url: u); r.httpMethod = method; r.httpBody = body; r.timeoutInterval = 20
        let pw = UserDefaults.standard.string(forKey: "pw") ?? ""
        r.setValue("Basic " + Data(("u:" + pw).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        return r
    }
    static func run(_ r: URLRequest?, _ done: @escaping (Data?) -> Void) {
        guard let r = r else { done(nil); return }
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 999) < 300
            DispatchQueue.main.async { done(ok ? (d ?? Data()) : nil) }
        }.resume()
    }
    static func upload(_ file: URL, _ done: @escaping (Bool) -> Void) {
        guard let r = req("/api/files?name=" + enc(file.lastPathComponent), "PUT") else { return done(false) }
        URLSession.shared.uploadTask(with: r, fromFile: file) { _, resp, _ in
            DispatchQueue.main.async { done(((resp as? HTTPURLResponse)?.statusCode ?? 999) < 300) }
        }.resume()
    }
}

final class Store {
    static let shared = Store()
    var reminders: [Reminder] = [], files: [RFile] = []
    func refresh(_ done: ((Bool) -> Void)? = nil) {
        API.run(API.req("/api/reminders")) { d in
            guard let d = d, let r = try? JSONDecoder().decode([Reminder].self, from: d) else { done?(false); return }
            self.reminders = r.sorted { $0.date < $1.date }
            self.schedule()
            API.run(API.req("/api/files")) { d in
                if let d = d, let f = try? JSONDecoder().decode([RFile].self, from: d) { self.files = f }
                NotificationCenter.default.post(name: .synced, object: nil)
                done?(true)
            }
        }
    }
    // Local notifications: they fire even when the app is closed (up to 60 upcoming).
    func schedule() {
        let c = UNUserNotificationCenter.current(); c.removeAllPendingNotificationRequests()
        for r in reminders.filter({ $0.date > Date() }).prefix(60) {
            let n = UNMutableNotificationContent(); n.title = r.title; n.body = r.notes.isEmpty ? timeFmt.string(from: r.date) : r.notes; n.sound = .default
            let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.date)
            c.add(UNNotificationRequest(identifier: r.id, content: n, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)))
        }
    }
}

extension UIViewController {
    func alert(_ m: String) { let a = UIAlertController(title: nil, message: m, preferredStyle: .alert); a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true) }
    func stack(_ items: [UIView]) {
        view.backgroundColor = .white
        let s = UIStackView(arrangedSubviews: items); s.axis = .vertical; s.spacing = 12; s.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(s)
        NSLayoutConstraint.activate([s.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            s.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), s.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)])
    }
}

class RemindersVC: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Reminders"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(pull), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .synced, object: nil)
    }
    override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); Store.shared.refresh() }
    @objc func reload() { refreshControl?.endRefreshing(); tableView.reloadData() }
    @objc func pull() { Store.shared.refresh { _ in self.reload() } }
    @objc func add() { navigationController?.pushViewController(AddVC(), animated: true) }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { Store.shared.reminders.count }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let r = Store.shared.reminders[i.row]; let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        c.textLabel?.text = r.title; c.detailTextLabel?.text = fmt.string(from: r.date) + (r.file.isEmpty ? "" : "  📎 " + r.file); return c
    }
    override func tableView(_ t: UITableView, commit e: UITableViewCell.EditingStyle, forRowAt i: IndexPath) {
        guard e == .delete else { return }
        API.run(API.req("/api/reminders/" + Store.shared.reminders[i.row].id, "DELETE")) { _ in Store.shared.refresh() }
    }
}

class AddVC: UIViewController, UIDocumentPickerDelegate {
    let tf = UITextField(), nf = UITextField(), dp = UIDatePicker(), at = UIButton(type: .system)
    var picked: URL?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "New reminder"
        tf.placeholder = "Title"; nf.placeholder = "Notes"; [tf, nf].forEach { $0.borderStyle = .roundedRect }
        dp.date = Date().addingTimeInterval(3600)
        at.setTitle("Attach file…", for: .normal); at.addTarget(self, action: #selector(pick), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        stack([tf, nf, dp, at])
    }
    @objc func pick() { let p = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import); p.delegate = self; present(p, animated: true) }
    func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { picked = urls.first; at.setTitle("📎 " + (urls.first?.lastPathComponent ?? ""), for: .normal) }
    @objc func save() {
        guard let title = tf.text, !title.isEmpty else { return alert("Enter a title") }
        let post = { (name: String) in
            let body = try? JSONSerialization.data(withJSONObject: ["title": title, "notes": self.nf.text ?? "", "time": iso.string(from: self.dp.date), "file": name])
            var r = API.req("/api/reminders", "POST", body: body); r?.setValue("application/json", forHTTPHeaderField: "Content-Type")
            API.run(r) { ok in
                if ok != nil { Store.shared.refresh(); self.navigationController?.popViewController(animated: true) } else { self.alert("Could not save") }
            }
        }
        if let f = picked { API.upload(f) { ok in if ok { post(f.lastPathComponent) } else { self.alert("Upload failed") } } } else { post("") }
    }
}

class CalendarVC: UITableViewController {
    var days: [(Date, [Reminder])] = []
    override func viewDidLoad() { super.viewDidLoad(); title = "Calendar"; NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .synced, object: nil) }
    override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); reload() }
    @objc func reload() {
        let g = Dictionary(grouping: Store.shared.reminders) { Calendar.current.startOfDay(for: $0.date) }
        days = g.keys.sorted().map { ($0, g[$0] ?? []) }; tableView.reloadData()
    }
    override func numberOfSections(in t: UITableView) -> Int { days.count }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { days[s].1.count }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { dayFmt.string(from: days[s].0) }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let r = days[i.section].1[i.row]; let c = UITableViewCell(style: .default, reuseIdentifier: nil)
        c.textLabel?.text = timeFmt.string(from: r.date) + "   " + r.title; return c
    }
}

class FilesVC: UITableViewController, UIDocumentPickerDelegate, UIDocumentInteractionControllerDelegate {
    var dic: UIDocumentInteractionController?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Files"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(pick))
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .synced, object: nil)
    }
    override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); Store.shared.refresh() }
    @objc func reload() { tableView.reloadData() }
    @objc func pick() { let p = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import); p.delegate = self; present(p, animated: true) }
    func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let u = urls.first else { return }
        API.upload(u) { ok in if ok { Store.shared.refresh() } else { self.alert("Upload failed") } }
    }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { Store.shared.files.count }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let f = Store.shared.files[i.row]; let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        c.textLabel?.text = f.name; c.detailTextLabel?.text = "\(f.size / 1024) KB"; return c
    }
    override func tableView(_ t: UITableView, commit e: UITableViewCell.EditingStyle, forRowAt i: IndexPath) {
        guard e == .delete else { return }
        API.run(API.req("/api/files/" + enc(Store.shared.files[i.row].name), "DELETE")) { _ in Store.shared.refresh() }
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        let f = Store.shared.files[i.row]
        guard let r = API.req("/api/files/" + enc(f.name)) else { return }
        URLSession.shared.downloadTask(with: r) { tmp, _, _ in
            guard let tmp = tmp else { return }
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
            try? FileManager.default.removeItem(at: dst); try? FileManager.default.moveItem(at: tmp, to: dst)
            DispatchQueue.main.async {
                let d = UIDocumentInteractionController(url: dst); d.delegate = self; self.dic = d
                if !d.presentPreview(animated: true) { d.presentOptionsMenu(from: self.view.bounds, in: self.view, animated: true) }
            }
        }.resume()
    }
    func documentInteractionControllerViewControllerForPreview(_ c: UIDocumentInteractionController) -> UIViewController { self }
}

class SettingsVC: UIViewController {
    let u = UITextField(), p = UITextField(), l = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Settings"
        u.placeholder = "http://192.168.1.50"; u.text = UserDefaults.standard.string(forKey: "url"); u.autocapitalizationType = .none; u.autocorrectionType = .no; u.keyboardType = .URL
        p.placeholder = "Password"; p.isSecureTextEntry = true; p.text = UserDefaults.standard.string(forKey: "pw")
        [u, p].forEach { $0.borderStyle = .roundedRect }
        let b = UIButton(type: .system); b.setTitle("Save & connect", for: .normal); b.addTarget(self, action: #selector(save), for: .touchUpInside)
        l.numberOfLines = 0; stack([u, p, b, l])
    }
    @objc func save() {
        UserDefaults.standard.set(u.text, forKey: "url"); UserDefaults.standard.set(p.text, forKey: "pw"); view.endEditing(true); l.text = "Connecting…"
        Store.shared.refresh { self.l.text = $0 ? "Connected ✓" : "Failed: check the address and password" }
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let nc = UNUserNotificationCenter.current(); nc.delegate = self; nc.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        a.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        let tabs = UITabBarController()
        let vcs: [(UIViewController, String)] = [(RemindersVC(), "Reminders"), (CalendarVC(style: .grouped), "Calendar"), (FilesVC(), "Files"), (SettingsVC(), "Settings")]
        tabs.viewControllers = vcs.map { let n = UINavigationController(rootViewController: $0.0); n.tabBarItem.title = $0.1; return n }
        window = UIWindow(frame: UIScreen.main.bounds); window?.rootViewController = tabs; window?.makeKeyAndVisible()
        if API.base.isEmpty { tabs.selectedIndex = 3 }
        return true
    }
    func application(_ a: UIApplication, performFetchWithCompletionHandler h: @escaping (UIBackgroundFetchResult) -> Void) { Store.shared.refresh { h($0 ? .newData : .failed) } }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.alert, .sound]) }
}
