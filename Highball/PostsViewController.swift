//
//  PostsViewController.swift
//  Highball
//
//  Created by Ian Ynda-Hummel on 10/26/14.
//  Copyright (c) 2014 ianynda. All rights reserved.
//

import UIKit
import WebKit

enum TextRow: Int {
    case Title
    case Body
}

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

let postHeaderViewIdentifier = "postHeaderViewIdentifier"
let titleTableViewCellIdentifier = "titleTableViewCellIdentifier"
let photosetRowTableViewCellIdentifier = "photosetRowTableViewCellIdentifier"
let contentTableViewCellIdentifier = "contentTableViewCellIdentifier"
let postQuestionTableViewCellIdentifier = "postQuestionTableViewCellIdentifier"
let postLinkTableViewCellIdentifier = "postLinkTableViewCellIdentifier"
let postDialogueEntryTableViewCellIdentifier = "postDialogueEntryTableViewCellIdentifier"
let videoTableViewCellIdentifier = "videoTableViewCellIdentifier"
let youtubeTableViewCellIdentifier = "youtubeTableViewCellIdentifier"
let postTagsTableViewCellIdentifier = "postTagsTableViewCellIdentifier"

class PostsViewController: UIViewController, UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate, UIViewControllerTransitioningDelegate, WKNavigationDelegate {
    var tableView: UITableView!

    private var heightComputationQueue: NSOperationQueue!
    private let requiredRefreshDistance: CGFloat = 60
    private let postParseQueue = dispatch_queue_create("postParseQueue", nil)
    
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var reblogViewController: QuickReblogViewController?

    var webViewCache: Array<WKWebView>!
    var bodyWebViewCache: Dictionary<Int, WKWebView>!
    var bodyHeightCache: Dictionary<Int, CGFloat>!
    var secondaryBodyWebViewCache: Dictionary<Int, WKWebView>!
    var secondaryBodyHeightCache: Dictionary<Int, CGFloat>!
    var heightCache: Dictionary<NSIndexPath, CGFloat>!

    var posts: Array<Post>!
    var topOffset = 0
    var bottomOffset = 0

    var loadingTop: Bool = false {
        didSet {
            if let navigationController = self.navigationController {
                navigationController.setIndeterminate(true)
                if self.loadingTop {
                    navigationController.showProgress()
                } else {
                    navigationController.cancelProgress()
                }
            }
        }
    }
    var loadingBottom = false
    var lastPoint: CGPoint?
    var loadingCompletion: (() -> ())?
    
    required override init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("resignActive:"), name: UIApplicationWillResignActiveNotification, object: nil)

        self.heightComputationQueue = NSOperationQueue()
        self.heightComputationQueue.underlyingQueue = dispatch_get_main_queue()

        self.loadingTop = false
        self.loadingBottom = false

        self.webViewCache = Array<WKWebView>()
        self.bodyWebViewCache = Dictionary<Int, WKWebView>()
        self.bodyHeightCache = Dictionary<Int, CGFloat>()
        self.secondaryBodyWebViewCache = Dictionary<Int, WKWebView>()
        self.secondaryBodyHeightCache = Dictionary<Int, CGFloat>()
        self.heightCache = Dictionary<NSIndexPath, CGFloat>()
        
        self.tableView = UITableView()
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.allowsSelection = true
        self.tableView.separatorStyle = UITableViewCellSeparatorStyle.None
        self.tableView.sectionHeaderHeight = 50
        self.tableView.sectionFooterHeight = 50
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.showsHorizontalScrollIndicator = false
        self.tableView.addInfiniteScrollingWithActionHandler {}

        self.tableView.registerClass(TitleTableViewCell.classForCoder(), forCellReuseIdentifier: titleTableViewCellIdentifier)
        self.tableView.registerClass(PhotosetRowTableViewCell.classForCoder(), forCellReuseIdentifier: photosetRowTableViewCellIdentifier)
        self.tableView.registerClass(ContentTableViewCell.classForCoder(), forCellReuseIdentifier: contentTableViewCellIdentifier)
        self.tableView.registerClass(PostQuestionTableViewCell.classForCoder(), forCellReuseIdentifier: postQuestionTableViewCellIdentifier)
        self.tableView.registerClass(PostLinkTableViewCell.classForCoder(), forCellReuseIdentifier: postLinkTableViewCellIdentifier)
        self.tableView.registerClass(PostDialogueEntryTableViewCell.classForCoder(), forCellReuseIdentifier: postDialogueEntryTableViewCellIdentifier)
        self.tableView.registerClass(TagsTableViewCell.classForCoder(), forCellReuseIdentifier: postTagsTableViewCellIdentifier)
        self.tableView.registerClass(VideoTableViewCell.classForCoder(), forCellReuseIdentifier: videoTableViewCellIdentifier)
        self.tableView.registerClass(YoutubeTableViewCell.classForCoder(), forCellReuseIdentifier: youtubeTableViewCellIdentifier)
        self.tableView.registerClass(PostHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: postHeaderViewIdentifier)
        
        self.view.addSubview(self.tableView)
        
        layout(self.tableView, self.view) { tableView, view in
            tableView.edges == view.edges; return
        }
        
        self.longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: Selector("didLongPress:"))
        self.longPressGestureRecognizer.delegate = self
        self.longPressGestureRecognizer.minimumPressDuration = 0.3
        self.view.addGestureRecognizer(self.longPressGestureRecognizer)

        self.panGestureRecognizer = UIPanGestureRecognizer(target: self, action: Selector("didPan:"))
        self.panGestureRecognizer.delegate = self
        self.view.addGestureRecognizer(self.panGestureRecognizer)

        let menuIcon = FAKIonIcons.iosGearOutlineIconWithSize(30);
        let menuIconImage = menuIcon.imageWithSize(CGSize(width: 30, height: 30))
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: menuIconImage,
            style: UIBarButtonItemStyle.Plain,
            target: self,
            action: Selector("navigate:event:")
        )
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        if let posts = self.posts {
            if countElements(posts) > 0 {
                return
            }
        }

        self.loadTop()
    }

    override func didReceiveMemoryWarning() {
        self.webViewCache.removeAll()
        super.didReceiveMemoryWarning()
    }

    func resignActive(notification: NSNotification) {
        self.webViewCache.removeAll()
    }

    func popWebView() -> WKWebView {
        let frame = CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: 1)

        if countElements(self.webViewCache) > 0 {
            let webView = self.webViewCache.removeAtIndex(0)
            webView.frame = frame
            return webView
        }

        let webView = WKWebView(frame: frame)
        webView.navigationDelegate = self
        return webView
    }

    func pushWebView(webView: WKWebView) {
        self.webViewCache.append(webView)
    }

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func postsFromJSON(json: JSON) -> Array<Post> { return [] }
    func requestPosts(parameters: Dictionary<String, AnyObject>, callback: TMAPICallback) { NSException().raise() }

    func loadTop() {
        if self.loadingTop {
            return
        }

        self.loadingTop = true

        if self.topOffset >= 20 {
            self.topOffset -= 20
        } else if self.topOffset > 0 {
            self.topOffset = 0
        }

        self.bottomOffset = 0

        self.requestPosts(["offset" : self.topOffset, "reblog_info" : "true"]) { (response: AnyObject!, error: NSError!) -> Void in
            if let e = error {
                println(e)
                self.loadingTop = false
            } else {
                dispatch_async(self.postParseQueue, {
                    let posts = self.postsFromJSON(JSON(response))
                    dispatch_async(dispatch_get_main_queue()) {
                        for post in posts {
                            self.heightComputationQueue.addOperationWithBlock() {
                                if let content = post.htmlBodyWithWidth(self.tableView.frame.size.width) {
                                    let webView = self.popWebView()
                                    let htmlString = content
                                    
                                    self.bodyWebViewCache[post.id] = webView
                                    
                                    webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
                                }
                            }
                            self.heightComputationQueue.addOperationWithBlock() {
                                if let content = post.htmlSecondaryBodyWithWidth(self.tableView.frame.size.width) {
                                    let webView = self.popWebView()
                                    let htmlString = content
                                    
                                    self.secondaryBodyWebViewCache[post.id] = webView
                                    
                                    webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
                                }
                            }
                        }

                        dispatch_async(dispatch_get_main_queue(), {
                            self.loadingCompletion = {
                                self.posts = posts
                                self.heightCache.removeAll()
                                self.tableView.reloadData()
                            }
                            self.reloadTable()
                        })
                    }
                })
            }
        }
    }
    
    func loadMore() {
        if self.loadingTop || self.loadingBottom {
            return
        }

        if let posts = self.posts {
            if let lastPost = posts.last {
                self.loadingBottom = true
                self.requestPosts(["offset" : self.topOffset + self.bottomOffset + 20, "reblog_info" : "true"]) { (response: AnyObject!, error: NSError!) -> Void in
                    if let e = error {
                        println(e)
                        self.loadingBottom = false
                    } else {
                        dispatch_async(self.postParseQueue, {
                            let posts = self.postsFromJSON(JSON(response)).filter { return $0.timestamp < lastPost.timestamp }
                            dispatch_async(dispatch_get_main_queue()) {
                                for post in posts {
                                    self.heightComputationQueue.addOperationWithBlock() {
                                        if let content = post.htmlBodyWithWidth(self.tableView.frame.size.width) {
                                            let webView = self.popWebView()
                                            let htmlString = content
                                            
                                            self.bodyWebViewCache[post.id] = webView
                                            
                                            webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
                                        }
                                    }
                                    self.heightComputationQueue.addOperationWithBlock() {
                                        if let content = post.htmlSecondaryBodyWithWidth(self.tableView.frame.size.width) {
                                            let webView = self.popWebView()
                                            let htmlString = content
                                            
                                            self.secondaryBodyWebViewCache[post.id] = webView
                                            
                                            webView.loadHTMLString(htmlString, baseURL: NSURL(string: ""))
                                        }
                                    }
                                }

                                dispatch_async(dispatch_get_main_queue(), {
                                    self.loadingCompletion = {
                                        let indexSet = NSIndexSet(indexesInRange: NSMakeRange(self.posts.count, posts.count))

                                        self.posts.extend(posts)
                                        self.bottomOffset += posts.count
                                        
                                        self.tableView.insertSections(indexSet, withRowAnimation: UITableViewRowAnimation.None)
                                    }
                                    self.reloadTable()
                                })
                            }
                        })
                    }
                }
            }
        }
    }

    func navigate(sender: UIBarButtonItem, event: UIEvent) {
        if let touches = event.allTouches() {
            if let touch = touches.anyObject() as? UITouch {
                if let navigationController = self.navigationController {
                    let viewController = QuickNavigateController()
                    
                    viewController.startingPoint = touch.locationInView(self.view)
                    viewController.modalPresentationStyle = UIModalPresentationStyle.OverFullScreen
                    viewController.modalTransitionStyle = UIModalTransitionStyle.CrossDissolve
                    viewController.view.bounds = navigationController.view.bounds

                    viewController.completion = { navigateOption in
                        if let option = navigateOption {
                            switch(option) {
                            case .Dashboard:
                                navigationController.setViewControllers([DashboardViewController()], animated: false)
                            case .Likes:
                                navigationController.setViewControllers([LikesViewController()], animated: false)
                            case .Settings:
                                navigationController.dismissViewControllerAnimated(true, completion: { () -> Void in
                                    let settingsViewController = SettingsViewController(style: UITableViewStyle.Grouped)
                                    let settingsNavigationViewController = UINavigationController(rootViewController: settingsViewController)
                                    navigationController.presentViewController(settingsNavigationViewController, animated: true, completion: nil)
                                })
                                return
                            }
                        }
                        navigationController.dismissViewControllerAnimated(true, completion: nil)
                    }
                    
                    navigationController.presentViewController(viewController, animated: true, completion: nil)
                }
            }
        }
    }

    func reblogBlogName() -> (String) {
        return ""
    }

    func reloadTable() {
        if self.heightComputationQueue.operationCount > 0 {
            return
        }

        if let posts = self.posts {
            for post in posts {
                if let content = post.body {
                    if let webView = self.bodyWebViewCache[post.id] {
                        return
                    }
                } else if let content = post.secondaryBody {
                    if let webView = self.secondaryBodyWebViewCache[post.id] {
                        return
                    }
                }
            }
        }

        self.tableView.infiniteScrollingView.stopAnimating()
        if self.loadingTop || self.loadingBottom {
            if let completion = self.loadingCompletion {
                completion()
            }
        }

        self.loadingCompletion = nil
        self.loadingTop = false
        self.loadingBottom = false
    }
    
    func didLongPress(sender: UILongPressGestureRecognizer) {
        if sender.state == UIGestureRecognizerState.Began {
            self.tableView.scrollEnabled = false
            let point = sender.locationInView(self.navigationController!.view)
            let tableViewPoint = sender.locationInView(self.tableView)
            if let indexPath = self.tableView.indexPathForRowAtPoint(tableViewPoint) {
                if let cell = self.tableView.cellForRowAtIndexPath(indexPath) {
                    let post = self.posts[indexPath.section]
                    let viewController = QuickReblogViewController()
                    
                    viewController.startingPoint = point
                    viewController.post = post
                    viewController.transitioningDelegate = self
                    viewController.modalPresentationStyle = UIModalPresentationStyle.Custom
                    
                    viewController.view.bounds = self.navigationController!.view.bounds
                    
                    self.navigationController!.view.addSubview(viewController.view)
                    
                    viewController.view.layoutIfNeeded()
                    viewController.viewDidAppear(false)
                    
                    self.reblogViewController = viewController
                }
            }
        } else if sender.state == UIGestureRecognizerState.Ended {
            self.tableView.scrollEnabled = true
            if let viewController = self.reblogViewController {
                let point = viewController.startingPoint
                let tableViewPoint = tableView.convertPoint(point, fromView: self.navigationController!.view)
                if let indexPath = self.tableView.indexPathForRowAtPoint(tableViewPoint) {
                    if let cell = self.tableView.cellForRowAtIndexPath(indexPath) {
                        let post = self.posts[indexPath.section]
                        
                        if let quickReblogAction = viewController.reblogAction() {
                            switch quickReblogAction {
                            case .Reblog(let reblogType):
                                let reblogViewController = TextReblogViewController()
                                
                                reblogViewController.reblogType = reblogType
                                reblogViewController.post = post
                                reblogViewController.blogName = self.reblogBlogName()
                                reblogViewController.bodyHeightCache = self.bodyHeightCache
                                reblogViewController.secondaryBodyHeightCache = self.secondaryBodyHeightCache
                                reblogViewController.modalPresentationStyle = UIModalPresentationStyle.OverFullScreen
                                reblogViewController.modalTransitionStyle = UIModalTransitionStyle.CrossDissolve
                                
                                self.presentViewController(reblogViewController, animated: true, completion: nil)
                            case .Share:
                                let postItemProvider = PostItemProvider(placeholderItem: "")
                                
                                postItemProvider.post = post
                                
                                var activityItems: Array<UIActivityItemProvider> = [ postItemProvider ]
                                if let photosetCell = cell as? PhotosetRowTableViewCell {
                                    if let image = photosetCell.imageAtPoint(self.view.convertPoint(point, toView: photosetCell)) {
                                        let imageItemProvider = ImageItemProvider(placeholderItem: image)
                                        
                                        imageItemProvider.image = image
                                        
                                        activityItems.append(imageItemProvider)
                                    }
                                }
                                
                                let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                                self.presentViewController(activityViewController, animated: true, completion: nil)
                            case .Like:
                                if post.liked.boolValue {
                                    TMAPIClient.sharedInstance().unlike("\(post.id)", reblogKey: post.reblogKey, callback: { (response, error) -> Void in
                                        if let e = error {
                                            println(e)
                                        } else {
                                            post.liked = false
                                        }
                                    })
                                } else {
                                    TMAPIClient.sharedInstance().like("\(post.id)", reblogKey: post.reblogKey, callback: { (response, error) -> Void in
                                        if let e = error {
                                            println(e)
                                        } else {
                                            post.liked = true
                                        }
                                    })
                                }
                            }
                        }
                    }
                }
                
                viewController.view.removeFromSuperview()
            }
            
            self.reblogViewController = nil
        }
    }
    
    func didPan(sender: UIPanGestureRecognizer) {
        if let viewController = self.reblogViewController {
            viewController.updateWithPoint(sender.locationInView(viewController.view))
        }
    }
    
    // MARK: UITableViewDataSource
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if let posts = self.posts {
            return posts.count
        }
        return 0
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let post = self.posts[section]
        var rowCount = 0
        switch post.type {
        case "photo":
            let postPhotos = post.photos
            if postPhotos.count == 1 {
                rowCount = 2
            }
            rowCount = post.layoutRows.count + 1
        case "text":
            rowCount = 2
        case "answer":
            rowCount = 2
        case "quote":
            rowCount = 2
        case "link":
            rowCount = 2
        case "chat":
            rowCount = 1 + post.dialogueEntries.count
        case "video":
            rowCount = 2
        case "audio":
            rowCount = 2
        default:
            rowCount = 0
        }

        return rowCount + 1
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let post = posts[indexPath.section]
        let cell = self.tableView(tableView, cellForRowAtIndexPath: indexPath, post: post)

        cell.selectionStyle = UITableViewCellSelectionStyle.None

        return cell
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath, post: Post) -> UITableViewCell {
        if indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1 {
            let cell = tableView.dequeueReusableCellWithIdentifier(postTagsTableViewCellIdentifier) as TagsTableViewCell!
            cell.tags = post.tags
            return cell
        }

        switch post.type {
        case "photo":
            if indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 2 {
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            }
            let cell = tableView.dequeueReusableCellWithIdentifier(photosetRowTableViewCellIdentifier) as PhotosetRowTableViewCell!
            let postPhotos = post.photos

            cell.contentWidth = tableView.frame.size.width

            if postPhotos.count == 1 {
                cell.images = postPhotos
            } else {
                let photosetLayoutRows = post.layoutRows
                var photosIndexStart = 0
                for photosetLayoutRow in photosetLayoutRows[0..<indexPath.row] {
                    photosIndexStart += photosetLayoutRow
                }
                let photosetLayoutRow = photosetLayoutRows[indexPath.row]
                
                cell.images = Array(postPhotos[(photosIndexStart)..<(photosIndexStart + photosetLayoutRow)])
            }
            
            return cell
        case "text":
            switch TextRow(rawValue: indexPath.row)! {
            case .Title:
                let cell = tableView.dequeueReusableCellWithIdentifier(titleTableViewCellIdentifier) as TitleTableViewCell!
                cell.titleLabel.text = post.title
                return cell
            case .Body:
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            }
        case "answer":
            switch AnswerRow(rawValue: indexPath.row)! {
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
            switch QuoteRow(rawValue: indexPath.row)! {
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
            switch LinkRow(rawValue: indexPath.row)! {
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
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCellWithIdentifier(titleTableViewCellIdentifier) as TitleTableViewCell!
                cell.titleLabel.text = post.title
                return cell;
            }
            let dialogueEntry = post.dialogueEntries[indexPath.row - 1]
            let cell = tableView.dequeueReusableCellWithIdentifier(postDialogueEntryTableViewCellIdentifier) as PostDialogueEntryTableViewCell!
            cell.dialogueEntry = dialogueEntry
            return cell
        case "video":
            switch VideoRow(rawValue: indexPath.row)! {
            case .Player:
                switch post.videoType! {
                case "youtube":
                    let cell = tableView.dequeueReusableCellWithIdentifier(youtubeTableViewCellIdentifier) as YoutubeTableViewCell!
                    cell.post = post
                    return cell
                default:
                    let cell = tableView.dequeueReusableCellWithIdentifier(videoTableViewCellIdentifier) as VideoTableViewCell!
                    cell.post = post
                    return cell
                }
            case .Caption:
                let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
                cell.content = post.htmlBodyWithWidth(tableView.frame.size.width)
                return cell
            }
        case "audio":
            let cell = tableView.dequeueReusableCellWithIdentifier(contentTableViewCellIdentifier) as ContentTableViewCell!
            switch AudioRow(rawValue: indexPath.row)! {
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
    
    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let post = posts[section]
        let view = tableView.dequeueReusableHeaderFooterViewWithIdentifier(postHeaderViewIdentifier) as PostHeaderView
        
        view.post = post
        
        return view
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        let post = posts[indexPath.section]

        if indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1 {
            if post.tags.count > 0 {
                return 30
            }
            return 0
        }

        switch post.type {
        case "photo":
            if indexPath.row == self.tableView(tableView, numberOfRowsInSection: indexPath.section) - 2 {
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }

            if let height = self.heightCache[indexPath] {
                return height
            }

            let postPhotos = post.photos
            var images: Array<PostPhoto>!
            
            if postPhotos.count == 1 {
                images = postPhotos
            } else {
                let photosetLayoutRows = post.layoutRows
                var photosIndexStart = 0
                for photosetLayoutRow in photosetLayoutRows[0..<indexPath.row] {
                    photosIndexStart += photosetLayoutRow
                }
                let photosetLayoutRow = photosetLayoutRows[indexPath.row]
                
                images = Array(postPhotos[(photosIndexStart)..<(photosIndexStart + photosetLayoutRow)])
            }
            
            let imageCount = images.count
            let imageWidth = tableView.frame.size.width / CGFloat(images.count)
            let minHeight = floor(images.map { (image: PostPhoto) -> CGFloat in
                let scale = image.height / image.width
                return imageWidth * scale
                }.reduce(CGFloat.max, combine: { min($0, $1) }))

            self.heightCache[indexPath] = minHeight

            return minHeight
        case "text":
            switch TextRow(rawValue: indexPath.row)! {
            case .Title:
                if let title = post.title {
                    if let height = self.heightCache[indexPath] {
                        return height
                    }

                    let height = TitleTableViewCell.heightForTitle(title, width: tableView.frame.size.width)
                    self.heightCache[indexPath] = height
                    return height
                }
                return 0
            case .Body:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "answer":
            switch AnswerRow(rawValue: indexPath.row)! {
            case .Question:
                if let height = self.heightCache[indexPath] {
                    return height
                }

                let height = PostQuestionTableViewCell.heightForPost(post, width: tableView.frame.size.width)
                self.heightCache[indexPath] = height
                return height
            case .Answer:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "quote":
            switch QuoteRow(rawValue: indexPath.row)! {
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
            switch LinkRow(rawValue: indexPath.row)! {
            case .Link:
                if let height = self.heightCache[indexPath] {
                    return height
                }

                let height = PostLinkTableViewCell.heightForPost(post, width: tableView.frame.size.width)
                self.heightCache[indexPath] = height
                return height
            case .Description:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "chat":
            if indexPath.row == 0 {
                if let title = post.title {
                    if let height = self.heightCache[indexPath] {
                        return height
                    }

                    let height = TitleTableViewCell.heightForTitle(title, width: tableView.frame.size.width)
                    self.heightCache[indexPath] = height
                    return height
                }
                return 0
            }
            let dialogueEntry = post.dialogueEntries[indexPath.row - 1]
            if let height = self.heightCache[indexPath] {
                return height
            }

            let height = PostDialogueEntryTableViewCell.heightForPostDialogueEntry(dialogueEntry, width: tableView.frame.size.width)
            self.heightCache[indexPath] = height
            return height
        case "video":
            switch VideoRow(rawValue: indexPath.row)! {
            case .Player:
                if let height = self.heightCache[indexPath] {
                    return height
                }
                if let height = post.videoHeightWidthWidth(tableView.frame.size.width) {
                    self.heightCache[indexPath] = height
                    return height
                }
                self.heightCache[indexPath] = 320
                return 320
            case .Caption:
                if let height = self.bodyHeightCache[post.id] {
                    return height
                }
                return 0
            }
        case "video":
            switch AudioRow(rawValue: indexPath.row)! {
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

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if let cell = tableView.cellForRowAtIndexPath(indexPath) {
            if let photosetRowCell = cell as? PhotosetRowTableViewCell {
                let post = self.posts[indexPath.section]
                let viewController = ImagesViewController()

                viewController.post = post

                self.presentViewController(viewController, animated: true, completion: nil)
            } else if let videoCell = cell as? VideoPlaybackCell {
                if videoCell.isPlaying() {
                    videoCell.stop()
                } else {
                    let viewController = VideoPlayController(completion: { play in
                        if play {
                            videoCell.play()
                        }
                    })
                    viewController.modalPresentationStyle = UIModalPresentationStyle.OverCurrentContext
                    viewController.modalTransitionStyle = UIModalTransitionStyle.CrossDissolve
                    self.presentViewController(viewController, animated: true, completion: nil)
                }
            }
        }
    }

    func tableView(tableView: UITableView, didEndDisplayingCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        if let photosetRowCell = cell as? PhotosetRowTableViewCell {
            photosetRowCell.cancelDownloads()
        } else if let contentCell = cell as? ContentTableViewCell {
            contentCell.content = nil
        }
    }
    
    // MARK: UIScrollViewDelegate
    
    func scrollViewDidScroll(scrollView: UIScrollView) {
        let distanceFromBottom = scrollView.contentSize.height - scrollView.frame.size.height - scrollView.contentOffset.y

        if distanceFromBottom < 2000 {
            self.loadMore()
        }

        if !self.loadingTop {
            if let navigationController = self.navigationController {
                navigationController.setIndeterminate(false)
                if scrollView.contentOffset.y < 0 {
                    let distanceFromTop = scrollView.contentOffset.y + scrollView.contentInset.top + requiredRefreshDistance
                    let progress = 1 - max(min(distanceFromTop / requiredRefreshDistance, 1), 0)
                    navigationController.showProgress()
                    navigationController.setProgress(progress, animated: false)
                } else {
                    navigationController.cancelProgress()
                }
            }
        }
    }
    
    func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let distanceFromTop = scrollView.contentOffset.y + scrollView.contentInset.top
        if -distanceFromTop > self.requiredRefreshDistance {
            self.loadTop()
        }
    }
    
    // MARK: WKNavigationDelegate

    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        webView.getDocumentHeight { height in
            if let postId = self.bodyWebViewCache.keyForObject(webView, isEqual: ==) {
                self.bodyHeightCache[postId] = height
                self.bodyWebViewCache[postId] = nil
                self.reloadTable()
            } else if let postId = self.secondaryBodyWebViewCache.keyForObject(webView, isEqual: ==) {
                self.secondaryBodyHeightCache[postId] = height
                self.secondaryBodyWebViewCache[postId] = nil
                self.reloadTable()
            }

            self.pushWebView(webView)
        }
    }

    func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
        if let postId = self.bodyWebViewCache.keyForObject(webView, isEqual: ==) {
            self.bodyHeightCache[postId] = 0
            self.bodyWebViewCache[postId] = nil
            self.reloadTable()
        } else if let postId = self.secondaryBodyWebViewCache.keyForObject(webView, isEqual: ==) {
            self.secondaryBodyHeightCache[postId] = 0
            self.secondaryBodyWebViewCache[postId] = nil
            self.reloadTable()
        }
        
        self.pushWebView(webView)
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

extension WKWebView {
    func getDocumentHeight(completion: (CGFloat) -> ()) {
        self.evaluateJavaScript("var body = document.body, html = document.documentElement;Math.max( body.scrollHeight, body.offsetHeight,html.clientHeight, html.scrollHeight, html.offsetHeight );", completionHandler: { result, error in
            if let e = error {
                completion(0)
            } else if let height = JSON(result).int {
                completion(CGFloat(height))
            } else {
                completion(0)
            }
        })
    }
}

extension Dictionary {
    func keyForObject(object: Value!, isEqual: (Value!, Value!) -> (Bool)) -> (Key?) {
        for key in self.keys {
            if isEqual(object, self[key] as Value!) {
                return key
            }
        }
        return nil
    }
}
