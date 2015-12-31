//
//  TextReblogViewController.swift
//  Highball
//
//  Created by Ian Ynda-Hummel on 10/17/14.
//  Copyright (c) 2014 ianynda. All rights reserved.
//

import Cartography
import FontAwesomeKit
import SlackTextViewController
import TMTumblrSDK
import UIKit

class TextReblogViewController: SLKTextViewController {
    let reblogType: ReblogType
    let post: Post
    let blogName: String
    let bodyHeight: CGFloat?
    let secondaryBodyHeight: CGFloat?
    let height: CGFloat

    private var reblogging = false
    private var tableViewAdapter: TextReblogTableViewAdapter!

    init(post: Post, reblogType: ReblogType, blogName: String, bodyHeight: CGFloat?, secondaryBodyHeight: CGFloat?, height: CGFloat) {
        self.post = post
        self.reblogType = reblogType
        self.blogName = blogName
        self.bodyHeight = bodyHeight
        self.secondaryBodyHeight = secondaryBodyHeight
        self.height = height
        super.init(tableViewStyle: .Plain)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        var reblogTitle: String
        switch reblogType {
        case .Reblog:
            reblogTitle = "Reblog"
        case .Queue:
            reblogTitle = "Queue"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .Cancel,
            target: self,
            action: "cancel"
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: reblogTitle,
            style: .Done,
            target: self,
            action: "reblog"
        )

        navigationController?.view.backgroundColor = UIColor.clearColor()
        view.backgroundColor = UIColor.clearColor()

        let postViewController = PostViewController()
        postViewController.post = post
        postViewController.bodyHeight = bodyHeight
        postViewController.secondaryBodyHeight = secondaryBodyHeight

        self.tableViewAdapter = TextReblogTableViewAdapter(
            tableView: tableView,
            post: post,
            postViewController: postViewController,
            height: height
        )

        textInputbar.rightButton.setTitle("Add", forState: .Normal)
        textInputbar.autoHideRightButton = false

        let blurEffect = UIBlurEffect(style: .Light)
        let blurView = UIVisualEffectView(effect: blurEffect)
        let vibrancyEffect = UIVibrancyEffect(forBlurEffect: blurEffect)
        let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        view.insertSubview(vibrancyView, atIndex: 0)
        view.insertSubview(blurView, atIndex: 0)
        
        constrain(blurView, view) { blurView, view in
            blurView.edges == view.edges
        }
        constrain(vibrancyView, view) { vibrancyView, view in
            vibrancyView.edges == view.edges
        }
    }

    func cancel() {
        dismissViewControllerAnimated(true, completion: nil)
    }

    func reblog() {
        var parameters = [ "id" : "\(post.id)", "reblog_key" : post.reblogKey ]
        
        switch reblogType {
        case .Reblog:
            parameters["state"] = "published"
        case .Queue:
            parameters["state"] = "queue"
        }
        
        parameters["comment"] = tableViewAdapter.comment

        if tableViewAdapter.tags.count > 0 {
            parameters["tags"] = tableViewAdapter.tags.joinWithSeparator(",")
        }

        reblogging = true
        
        TMAPIClient.sharedInstance().reblogPost(blogName, parameters: parameters) { response, error in
            if let error = error {
                let alertController = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .Alert)
                alertController.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                self.presentViewController(alertController, animated: true, completion: nil)
            } else {
                self.dismissViewControllerAnimated(true, completion: nil)
            }
        }
    }

    override func canPressRightButton() -> Bool {
        return !reblogging && super.canPressRightButton()
    }

    override func didPressRightButton(sender: AnyObject!) {
        defer {
            super.didPressRightButton(sender)
        }

        guard tableViewAdapter.comment != nil else {
            tableViewAdapter.comment = textView.text
            tableView.reloadData()
            return
        }

        tableViewAdapter.tags.append(textView.text)
        tableView.reloadData()
    }
}
