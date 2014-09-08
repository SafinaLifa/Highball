//
//  MainViewController.swift
//  Highball
//
//  Created by Ian Ynda-Hummel on 8/24/14.
//  Copyright (c) 2014 ianynda. All rights reserved.
//

import UIKit

enum AnswerRow: Int {
    case Question
    case Answer
}

enum QuoteRow: Int {
    case Quote
    case Source
}

enum LinkRow: Int {
    case Link
    case Description
}

enum VideoRow: Int {
    case Player
    case Caption
}

enum AudioRow: Int {
    case Player
    case Caption
}

class MainViewController: UITableViewController, UIViewControllerTransitioningDelegate, UIWebViewDelegate {
    private let postHeaderViewIdentifier = "postHeaderViewIdentifier"
    private let photosetRowTableViewCellIdentifier = "photosetRowTableViewCellIdentifier"
    private let contentTableViewCellIdentifier = "contentTableViewCellIdentifier"
    private let postQuestionTableViewCellIdentifier = "postQuestionTableViewCellIdentifier"
    private let postLinkTableViewCellIdentifier = "postLinkTableViewCellIdentifier"
    private let postDialogueEntryTableViewCellIdentifier = "postDialogueEntryTableViewCellIdentifier"

    private let requiredRefreshDistance: CGFloat = 60

    var bodyWebViewCache: Dictionary<Int, UIWebView>!
    var bodyHeightCache: Dictionary<Int, CGFloat>!
    var secondaryBodyWebViewCache: Dictionary<Int, UIWebView>!
    var secondaryBodyHeightCache: Dictionary<Int, CGFloat>!

    var blogs: Array<Blog>!
    var primaryBlog: Blog! {
        didSet {
            self.navigationItem.title = self.primaryBlog.name
        }
    }
    var posts: Array<Post>! {
        didSet {
            self.reloadTable()
        }
    }

    var currentOffset: Int?
    var loadingTop: Bool? {
        didSet {
            self.navigationController!.setIndeterminate(true)
            if let loadingTop = self.loadingTop {
                if loadingTop {
                    self.navigationController!.showProgress()
                } else {
                    self.navigationController!.cancelProgress()
                }
            }
        }
    }
    var loadingBottom: Bool?
    var loggingIn = false
    var lastPoint: CGPoint?

    required override init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    func login() {
        if self.loggingIn {
            return
        }

        self.loggingIn = true

        if let oauthToken = TMAPIClient.sharedInstance().OAuthToken {
            TMAPIClient.sharedInstance().userInfo { response, error in
                if let e = error {
                    println(e)
                    return
                }

                let json = JSONValue(response)
                println(json)

                self.blogs = json["user"]["blogs"].array!.map({ Blog(json: $0) })
                self.primaryBlog = self.blogs.filter({ $0.primary }).first

                self.loadTop()
            }
        } else {
            TMAPIClient.sharedInstance().authenticate("highballtumblr") { (error: NSError!) -> Void in
                self.loggingIn = false

                if error == nil {
                    NSUserDefaults.standardUserDefaults().setObject(TMAPIClient.sharedInstance().OAuthToken, forKey: "HighballOAuthToken")
                    NSUserDefaults.standardUserDefaults().setObject(TMAPIClient.sharedInstance().OAuthTokenSecret, forKey: "HighballOAuthTokenSecret")

                    self.login()
                }
            }
        }
    }

//    func reblogPost(post: Post, type: ReblogType) {
//        var parameters = [ "id" : post.id.description, "reblog_key" : post.reblogKey ]
//
//        switch type {
//        case .Reblog:
//            parameters["state"] = "published"
//        case .Queue:
//            parameters["state"] = "queue"
//        case .Schedule:
//            return
//        }
//
//        TMAPIClient.sharedInstance().reblogPost(self.primaryBlog.name, parameters: parameters) { response, error in
//            if let e = error {
//                println(e)
//            } else {
//                println("reblog success")
//            }
//        }
//    }

    func applicationDidBecomeActive(notification: NSNotification!) {
        self.login()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.loadingTop = false
        self.loadingBottom = false

        self.bodyWebViewCache = Dictionary<Int, UIWebView>()
        self.bodyHeightCache = Dictionary<Int, CGFloat>()
        self.secondaryBodyWebViewCache = Dictionary<Int, UIWebView>()
        self.secondaryBodyHeightCache = Dictionary<Int, CGFloat>()

        self.tableView.separatorStyle = UITableViewCellSeparatorStyle.None
        self.tableView.sectionHeaderHeight = 50
        self.tableView.sectionFooterHeight = 50
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.showsHorizontalScrollIndicator = false

        self.tableView.registerClass(PhotosetRowTableViewCell.classForCoder(), forCellReuseIdentifier: photosetRowTableViewCellIdentifier)
        self.tableView.registerClass(ContentTableViewCell.classForCoder(), forCellReuseIdentifier: contentTableViewCellIdentifier)
        self.tableView.registerClass(PostQuestionTableViewCell.classForCoder(), forCellReuseIdentifier: postQuestionTableViewCellIdentifier)
        self.tableView.registerClass(PostLinkTableViewCell.classForCoder(), forCellReuseIdentifier: postLinkTableViewCellIdentifier)
        self.tableView.registerClass(PostDialogueEntryTableViewCell.classForCoder(), forCellReuseIdentifier: postDialogueEntryTableViewCellIdentifier)
        self.tableView.registerClass(PostHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: postHeaderViewIdentifier)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("applicationDidBecomeActive:"), name: UIApplicationDidBecomeActiveNotification, object: nil)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        self.login()
    }

    func loadTop() {
        if self.loadingTop! {
            return
        }

        self.loadingTop = true

        TMAPIClient.sharedInstance().dashboard([:]) { (response: AnyObject!, error: NSError!) -> Void in
            if let e = error {
                println(e)
                return
            }
            let json = JSONValue(response)
            let posts = json["posts"].array!.map { (post) -> (Post) in
                return Post(json: post)
            }

            for post in posts {
                if let content = post.htmlBodyWithWidth(self.view.frame.size.width) {
                    let webView = UIWebView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 1))
                    let htmlString = content

                    webView.delegate = self
                    webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
        
                    self.bodyWebViewCache[post.id] = webView
                }

                if let content = post.htmlSecondaryBodyWithWidth(self.view.frame.size.width) {
                    let webView = UIWebView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 1))
                    let htmlString = content

                    webView.delegate = self
                    webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
        
                    self.secondaryBodyWebViewCache[post.id] = webView
                }
                    
//                println(post.json)
            }

            self.posts = posts
            self.currentOffset = 0

            self.loadingTop = false
        }
    }

    func loadMore() {
        if self.loadingTop! || self.loadingBottom! {
            return
        }

        if let posts = self.posts {
            if let lastPost = posts.last {
                self.loadingBottom = true
                TMAPIClient.sharedInstance().dashboard(["offset" : self.currentOffset! + 20]) { (response: AnyObject!, error: NSError!) -> Void in
                    if let e = error {
                        println(e)
                        return
                    }
                    let json = JSONValue(response)
                    let posts = json["posts"].array!.map { (post) -> (Post) in
                        return Post(json: post)
                    }.filter { (post) -> (Bool) in
                        return post.type == "photo" || post.type == "text"
                    }
                    
                    for post in posts {
                        if let content = post.htmlBodyWithWidth(self.view.frame.size.width) {
                            let webView = UIWebView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 1))
                            let htmlString = content
                            
                            webView.delegate = self
                            webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
                            
                            self.bodyWebViewCache[post.id] = webView
                        }
                        
//                        println(post.json)
                    }

                    self.posts.extend(posts)
                    self.currentOffset! += 20
                    self.reloadTable()

                    self.loadingBottom = false
                }
            }
        }
    }

    func reloadTable() {
        if let posts = self.posts {
            var webViewsFinishedLoading = true
            for post in posts {
                if let content = post.body() {
                    if let height = self.bodyHeightCache[post.id] {} else {
                        return
                    }
                } else if let content = post.secondaryBody() {
                    if let height = self.secondaryBodyHeightCache[post.id] {} else {
                        return
                    }
                }
            }
        }

        self.tableView?.reloadData()
    }

    // MARK: UITableViewDataSource

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if let posts = self.posts {
            return posts.count
        }
        return 0
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let post = self.posts[section]
        switch post.type {
        case "photo":
            let postPhotos = post.photos()
            if postPhotos.count == 1 {
                return 2
            }

            return post.layoutRows().count + 1
        case "text":
            return 1
        case "answer":
            return 2
        case "quote":
            return 2
        case "link":
            return 2
        case "chat":
            return post.dialogueEntries().count
        case "video":
            return 2
        case "audio":
            return 2
        default:
            return 0
        }
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let post = posts[indexPath.section]
        switch post.type {
        case "photo":
            if indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1 {
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            }

            let cell = tableView.dequeueReusableCellWithIdentifier(photosetRowTableViewCellIdentifier) as PhotosetRowTableViewCell!
            let postPhotos = post.photos()
            if postPhotos.count == 1 {
                cell.images = postPhotos
            } else {
                let photosetLayoutRows = post.layoutRows()
                var photosIndexStart = 0
                for photosetLayoutRow in photosetLayoutRows[0..<indexPath.row] {
                    photosIndexStart += photosetLayoutRow
                }
                let photosetLayoutRow = photosetLayoutRows[indexPath.row]

                cell.images = Array(postPhotos[(photosIndexStart)..<(photosIndexStart + photosetLayoutRow)])
            }
            cell.contentWidth = tableView.frame.size.width

            return cell
        case "text":
            let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
            cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
            return cell
        case "answer":
            switch AnswerRow.fromRaw(indexPath.row)! {
            case .Question:
                let cell = tableView.dequeueReusableCellWithIdentifier(postQuestionTableViewCellIdentifier) as PostQuestionTableViewCell!
                cell.post = post
                return cell
            case .Answer:
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            }
        case "quote":
            switch QuoteRow.fromRaw(indexPath.row)! {
            case .Quote:
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            case .Source:
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlSecondaryBodyWithWidth(tableView.frame.size.width)
                return cell
            }
        case "link":
            switch LinkRow.fromRaw(indexPath.row)! {
            case .Link:
                let cell = tableView.dequeueReusableCellWithIdentifier(postLinkTableViewCellIdentifier) as PostLinkTableViewCell!
                cell.post = post
                return cell
            case .Description:
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            }
        case "chat":
            let dialogueEntry = post.dialogueEntries()[indexPath.row]
            let cell = tableView.dequeueReusableCellWithIdentifier(postDialogueEntryTableViewCellIdentifier) as PostDialogueEntryTableViewCell!
            cell.dialogueEntry = dialogueEntry
            return cell
        case "video":
            let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
            switch VideoRow.fromRaw(indexPath.row)! {
            case .Player:
                cell.content = post.htmlSecondaryBodyWithWidth(tableView.frame.size.width)
            case .Caption:
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
            }
            return cell
        case "audio":
            let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
            switch AudioRow.fromRaw(indexPath.row)! {
            case .Player:
                cell.content = post.htmlSecondaryBodyWithWidth(tableView.frame.size.width)
            case .Caption:
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
            }
            return cell
        default:
            return tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as UITableViewCell!
        }
    }

    // MARK: UITableViewDelegate

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let post = posts[section]
        let view = tableView.dequeueReusableHeaderFooterViewWithIdentifier(postHeaderViewIdentifier) as PostHeaderView

        view.post = post

        weak var weakSelf = self

        view.quickReblogHandler = { sender in
            if let strongSelf = weakSelf {
                let startingPoint = sender.superview!.convertPoint(sender.center, toView: strongSelf.navigationController!.view)
                let viewController = QuickReblogViewController()

                viewController.startingPoint = startingPoint
                viewController.transitioningDelegate = self
                viewController.modalPresentationStyle = UIModalPresentationStyle.Custom

                strongSelf.presentViewController(viewController, animated: true, completion: nil)
            }
        }

        return view
    }

    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        let post = posts[indexPath.section]
        switch post.type {
        case "photo":
            if indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1 {
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }

            let postPhotos = post.photos()
            var images: Array<PostPhoto>!

            if postPhotos.count == 1 {
                images = postPhotos
            } else {
                let photosetLayoutRows = post.layoutRows()
                var photosIndexStart = 0
                for photosetLayoutRow in photosetLayoutRows[0..<indexPath.row] {
                    photosIndexStart += photosetLayoutRow
                }
                let photosetLayoutRow = photosetLayoutRows[indexPath.row]
            
                images = Array(postPhotos[(photosIndexStart)..<(photosIndexStart + photosetLayoutRow)])
            }

            let imageCount = images.count
            let imageWidth = tableView.frame.size.width / CGFloat(images.count)
            let minHeight = images.map { (image: PostPhoto) -> CGFloat in
                let scale = image.height() / image.width()
                return imageWidth * scale
            }.reduce(CGFloat.max, combine: { min($0, $1) })

            return minHeight
        case "text":
            if let height = self.bodyHeightCache[post.id] {
                return height
            }
            return 0
        case "answer":
            switch AnswerRow.fromRaw(indexPath.row)! {
            case .Question:
                return PostQuestionTableViewCell.heightForPost(post, width: tableView.frame.size.width)
            case .Answer:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "quote":
            switch QuoteRow.fromRaw(indexPath.row)! {
            case .Quote:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            case .Source:
                if let height = self.secondaryBodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "link":
            switch LinkRow.fromRaw(indexPath.row)! {
            case .Link:
                return PostLinkTableViewCell.heightForPost(post, width: tableView.frame.size.width)
            case .Description:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "chat":
            let dialogueEntry = post.dialogueEntries()[indexPath.row]
            return PostDialogueEntryTableViewCell.heightForPostDialogueEntry(dialogueEntry, width: tableView.frame.size.width)
        case "video":
            switch VideoRow.fromRaw(indexPath.row)! {
            case .Player:
                if let height = self.secondaryBodyHeightCache[post.id] {
                    return height
                }
                return 0
            case .Caption:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "video":
            switch AudioRow.fromRaw(indexPath.row)! {
            case .Player:
                if let height = self.secondaryBodyHeightCache[post.id] {
                    return height
                }
                return 0
            case .Caption:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        default:
            return 0
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if let cell = tableView.cellForRowAtIndexPath(indexPath) {
            if let photosetRowCell = cell as? PhotosetRowTableViewCell {
                let post = self.posts[indexPath.section]
                let viewController = ImagesViewController()

                viewController.post = post

                self.presentViewController(viewController, animated: true, completion: nil)
            }
        }
    }

    // MARK: UIScrollViewDelegate

    override func scrollViewDidScroll(scrollView: UIScrollView) {
        let distanceFromBottom = scrollView.contentSize.height - scrollView.frame.size.height - scrollView.contentOffset.y

        if distanceFromBottom < 2000 {
            self.loadMore()
        }

        if !self.loadingTop! {
            self.navigationController!.setIndeterminate(false)
            if scrollView.contentOffset.y < 0 {
                let distanceFromTop = scrollView.contentOffset.y + scrollView.contentInset.top + requiredRefreshDistance
                let progress = 1 - max(min(distanceFromTop / requiredRefreshDistance, 1), 0)
                self.navigationController!.showProgress()
                self.navigationController!.setProgress(progress, animated: false)
            } else {
                self.navigationController!.cancelProgress()
            }
        }

//        var sections = NSMutableIndexSet()
//        if let visibleIndexPaths = self.tableView.indexPathsForVisibleRows() as? Array<NSIndexPath> {
//            for indexPath in visibleIndexPaths {
//                if !sections.containsIndex(indexPath.section) {
//                    if let headerView = self.tableView.headerViewForSection(indexPath.section) as? PostHeaderView {
//                        sections.addIndex(indexPath.section)
//                        if headerView.reblogButton.showingOptions {
//                            headerView.reblogButton.showingOptions = false
//                        }
//                    }
//                }
//            }
//        }
    }

    override func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let distanceFromTop = scrollView.contentOffset.y + scrollView.contentInset.top
        if -distanceFromTop > self.requiredRefreshDistance {
            self.loadTop()
        }
    }

    // MARK: UIWebViewDelegate

    func webViewDidFinishLoad(webView: UIWebView!) {
        if let postId = self.bodyWebViewCache.keyForObject(webView, isEqual: ==) {
            self.bodyHeightCache[postId] = webView.documentHeight()
            self.bodyWebViewCache[postId] = nil
            self.reloadTable()
        } else if let postId = self.secondaryBodyWebViewCache.keyForObject(webView, isEqual: ==) {
            self.secondaryBodyHeightCache[postId] = webView.documentHeight()
            self.secondaryBodyWebViewCache[postId] = nil
            self.reloadTable()
        }
    }

    // MARK: UIViewControllerTransitioningDelegate

    func animationControllerForPresentedController(presented: UIViewController, presentingController presenting: UIViewController, sourceController source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return ReblogTransitionAnimator()
    }

    func animationControllerForDismissedController(dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animator = ReblogTransitionAnimator()

        animator.presenting = false

        return animator
    }
}

public extension UIWebView {
    func documentHeight() -> (CGFloat) {
        return CGFloat(self.stringByEvaluatingJavaScriptFromString("var body = document.body, html = document.documentElement;Math.max( body.scrollHeight, body.offsetHeight,html.clientHeight, html.scrollHeight, html.offsetHeight );")!.toInt()!)
    }
}

public extension Dictionary {
    func keyForObject(object: Value!, isEqual: (Value!, Value!) -> (Bool)) -> (Key?) {
        for key in self.keys {
            if isEqual(object, self[key] as Value!) {
                return key
            }
        }
        return nil
    }
}
