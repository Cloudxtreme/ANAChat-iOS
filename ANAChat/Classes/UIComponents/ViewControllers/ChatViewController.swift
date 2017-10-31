//
//  ChatViewController.swift
//

import UIKit
import CoreData
import MediaPlayer
import Photos
import AVKit
//import GooglePlacePicker
import MobileCoreServices

@objc protocol ChatViewControllerDelegate {
    //Implement below methods to implement custom external cells
    @objc optional func getExternalTableCell(cell indexPath:IndexPath, messageObject: External) -> UITableViewCell
    @objc optional func getExternalTableCell(heightAt indexPath:IndexPath , messageObject: External) -> CGFloat
    @objc optional func registerCells(_ tableView: UITableView)
}

@objc public class ChatViewController: BaseViewController ,MPMediaPickerControllerDelegate , UIImagePickerControllerDelegate , UINavigationControllerDelegate  , UIGestureRecognizerDelegate  , InputCellProtocolDelegate , ChatMediaCellDelegate ,UIDocumentMenuDelegate , UIDocumentPickerDelegate{

    let imagePickerController = UIImagePickerController()
    var inputTextView : InputTextFieldView!
    var inputOptionsView : InputOptionsView?
    var inputTypeButton : InputTypeButton?
    var inputDatePickerView : DatePickerView?
    
    public var businessId : String = ""
    public var headerTitle : String = "Chatty"
    public var headerDescription : String = "(ANA Intelligence agent)"
    public var headerLogoImageName : String = "chatty"
    public var baseThemeColor : UIColor = PreferencesManager.sharedInstance.getBaseThemeColor()
    public var senderThemeColor : UIColor = PreferencesManager.sharedInstance.getSenderThemeColor()
    public var baseAPIUrl : String!
    
    var contentFont : UIFont?
    
    var isTableViewScrolling = Bool()
    var visibleSectionIndex = Int()

    @IBOutlet weak var headerLogo: UIImageView!
    @IBOutlet weak var headerDescriptionLabel: UILabel!
    @IBOutlet weak var headerTitleLabel: UILabel!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var tableViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var inputContainerView: UIView!
    @IBOutlet weak var inputContainerViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var inputTextViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var textContainerView: UIView!
    @IBOutlet weak var textContainerViewHeightConstraint: NSLayoutConstraint!

    weak var delegate:ChatViewControllerDelegate?
    lazy var dataHelper = DataHelper()
    
    lazy var messagesFetchController:NSFetchedResultsController<Message>? = {
        let messagesFetchRequest = NSFetchRequest<Message>(entityName: "Message")
        let sortDescriptor = NSSortDescriptor(key: Constants.kTimeStampKey, ascending: true)
        
        messagesFetchRequest.sortDescriptors = [sortDescriptor]
        let frc = NSFetchedResultsController(fetchRequest: messagesFetchRequest, managedObjectContext: CoreDataContentManager.managedObjectContext(), sectionNameKeyPath: "dateStamp", cacheName: nil)
        frc.delegate = self
        frc.fetchRequest.shouldRefreshRefetchedObjects = true
        do {
            try frc.performFetch()
        }
        catch {
            print("Unable to fetch cart Objects")
        }
        return frc
    }()
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PreferencesManager.sharedInstance.configureBaseTheme(withColor: baseThemeColor)

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyBoardWillShow(withNotification:)), name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyBoardWillHide(withNotification:)), name: .UIKeyboardWillHide, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.notificationReceived(_:)), name: NSNotification.Name(rawValue: NotificationConstants.kMessageReceivedNotification), object: nil)
        self.navigationController?.navigationBar.isHidden = true
        self.headerView.backgroundColor = PreferencesManager.sharedInstance.getBaseThemeColor()
        if let baseUrl = self.baseAPIUrl , self.baseAPIUrl.characters.count > 0{
            APIManager.sharedInstance.configureAPIBaseUrl(withString: baseUrl)
        }else{
            self.didTappedBackButton()
        }
//        self.scrollToTableBottom()
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.navigationBar.isHidden = false
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillHide, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NotificationConstants.kMessageReceivedNotification), object: nil)
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        self.configureUI()
        self.loadHistory()
        // Do any additional setup after loading the view, typically from a nib.
    }

    func configureUI() {
        if let contentFont = self.contentFont{
            PreferencesManager.sharedInstance.configureContentText(withFont: contentFont)
        }
        PreferencesManager.sharedInstance.configureSenderTheme(withColor: senderThemeColor)
        PreferencesManager.sharedInstance.configureBaseTheme(withColor: baseThemeColor)
        PreferencesManager.sharedInstance.configureBusinessId(withText: businessId)
        headerTitleLabel.text = headerTitle
        headerDescriptionLabel.text = headerDescription
        headerLogo.image = UIImage.init(named: self.headerLogoImageName)

        self.isTableViewScrolling = true
        self.visibleSectionIndex = NSIntegerMax
        self.view.backgroundColor = UIConfigurationUtility.Colors.BackgroundColor
//        self.tableView.backgroundColor = UIConfigurationUtility.Colors.BackgroundColor
        self.tableView.contentInset  = UIEdgeInsetsMake(0, 0, 20, 0)
        self.title = "Chats"
        self.registerNibs()
        self.tapGestureRecognizers()
        self.scrollToTableBottom()
        ImageCache.sharedInstance.initilizeImageDirectory()
    }
    
    func loadHistory() {
        CoreDataContentManager.deleteAllWaitingPlaceholderImages { (success) in
            
        }
        if (self.messagesFetchController?.fetchedObjects?.count)! == 0{
            dataHelper.syncHistoryFromServer(successBlock: { (responseDict) in
                if (self.messagesFetchController?.fetchedObjects?.count)! > 0{
                    print(self.messagesFetchController?.fetchedObjects?.last ?? Message())
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                        if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                            self.loadInputView(lastObject)
                        }
                    }
                }
            })
        }else{
            DispatchQueue.main.async {
                self.tableView.reloadData()
                if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                    self.loadInputView(lastObject)
                }
            }
        }
    }
    
    func registerNibs(){
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UINib(nibName: "ChatReceiveTextCell", bundle: CommonUtility.getFrameworkBundle()), forCellReuseIdentifier: "receivetextcell")
        tableView.register(UINib(nibName: "ChatSenderTextCell", bundle: CommonUtility.getFrameworkBundle()), forCellReuseIdentifier: "sendtextcell")
        tableView.register(UINib(nibName: "ChatSenderMediaCell", bundle: CommonUtility.getFrameworkBundle()), forCellReuseIdentifier: "ChatSenderMediaCell")
        tableView.register(UINib(nibName: "ChatReceiverMediaCell", bundle: CommonUtility.getFrameworkBundle()), forCellReuseIdentifier: "ChatReceiverMediaCell")
        tableView.register(UINib(nibName: "ChatReceiveCarouselCell", bundle: CommonUtility.getFrameworkBundle()), forCellReuseIdentifier: "ChatReceiveCarouselCell")
        tableView.register(UINib(nibName: "TypingIndicatorCell", bundle: CommonUtility.getFrameworkBundle()), forCellReuseIdentifier: "TypingIndicatorCell")

        tableView.register(UINib(nibName: "CustomHeaderView", bundle: CommonUtility.getFrameworkBundle()), forHeaderFooterViewReuseIdentifier: "CustomHeaderView")
        
        self.delegate?.registerCells?(self.tableView)
    }
    
    func tapGestureRecognizers(){
        //Added tap gesture on tableview to recognize touch on tableview
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tableViewTapped(_:)))
        tapGesture.delegate = self
        self.tableView.addGestureRecognizer(tapGesture)
    }
    
    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func networkIsReachable() {
        if (dataHelper.getUnsentMessagesFromDB().count) > 0{
            for i in 0 ..< (dataHelper.getUnsentMessagesFromDB().count) {
                let messageObject = dataHelper.getUnsentMessagesFromDB()[i] as! Message
                var requestDict = RequestHelper.getRequestDictionary(messageObject, inputDict: nil)
                if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                    if var metaInfo = requestDict[Constants.kMetaKey] as? [String: Any]{
                        metaInfo[Constants.kResponseToKey] = lastObject.messageId
                        requestDict[Constants.kMetaKey] = metaInfo
                    }
                }

                dataHelper.sendMessageToServer(params: requestDict, apiPath: nil, messageObject: messageObject, completionHandler: { (response) in
                    self.reloadLastPreviousCell()
                })
            }
        }
    }
    
    func didTappedOnPlayButton(_ medialUrl: String){
        self.playVideo(view: self, mediaUrl: medialUrl)
    }
    
    func didTappedOnImageBackground(_ imageView: UIImageView){
        self.imageTap(imageView: imageView)
        /*
         let storyboard = UIStoryboard(name: "SDKMain", bundle: Bundle.main)
         let controller = storyboard.instantiateViewController(withIdentifier: "ZoomViewController") as! ZoomViewController
         controller.imageUrl = url
         self.navigationController?.pushViewController(controller, animated: true)
         */
    }
 
    func didTappedOnMap(_ latitude: Double , longitude : Double){
        let url = "http://maps.apple.com/maps?q=\(latitude),\(longitude)"
        UIApplication.shared.openURL(URL(string:url)!)
    }
    
    // MARK: -
    // MARK: UITapGestureRecognizer Helper Methods
    
    @objc func tableViewTapped(_ sender: UITapGestureRecognizer) {
        self.view.endEditing(true)
    }
    
    @IBAction func backButtonTapped(_ sender: Any) {
        self.didTappedBackButton()
    }
    
    func didTappedBackButton(){
        if self.navigationController != nil{
            self.navigationController?.popViewController(animated: true)
        }else{
            self.dismiss(animated: true, completion: {})
        }
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool{
        let buttonPosition = touch.view?.convert(CGPoint(x: 0,y :0), to: self.tableView)
        let tappedIndex = self.tableView.indexPathForRow(at: buttonPosition!)
        if (tappedIndex != nil){
            let cell = self.tableView.cellForRow(at: tappedIndex!)
            if cell is ChatReceiveTextCell || cell is ChatSenderTextCell || cell is ChatReceiveCarouselCell{
                self.view.endEditing(true)
                return false
            }
        }
        return true
    }

    // MARK: -
    // MARK: InputType Helper Methods
    
    func loadInputView(_ messageObject : Message){
        if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
            if lastObject.messageType == 2{
                if let inputObject = lastObject as? Input{
                    self.scrollToTableBottom()
                    if inputObject.inputInfo == nil{
                        switch inputObject.inputType{
                        case Int16(MessageInputType.MessageInputTypeText.rawValue),
                             Int16(MessageInputType.MessageInputTypeEmail.rawValue),
                             Int16(MessageInputType.MessageInputTypeNumeric.rawValue),
                             Int16(MessageInputType.MessageInputTypePhone.rawValue):
                                self.loadInputTypeText(lastObject)
                        case Int16(MessageInputType.MessageInputTypeOptions.rawValue):
                            if let inputTypeOptions = inputObject as? InputTypeOptions{
                                self.loadInputTypeOptions(inputTypeOptions)
                                print(inputTypeOptions)
                            }
                        case Int16(MessageInputType.MessageInputTypeList.rawValue):
                            if let inputTypeList = inputObject as? InputTypeOptions{
                                self.loadInputTypeMedia(inputObject)
                                print(inputTypeList)
                            }
                        case Int16(MessageInputType.MessageInputTypeMedia.rawValue):
                            if let inputTypeMedia = inputObject as? InputTypeMedia{
                                self.loadInputTypeMedia(inputObject)
                                print(inputTypeMedia)
                            }
                        case Int16(MessageInputType.MessageInputTypeDate.rawValue):
                            if let inputTypeDate = inputObject as? InputDate{
                                self.loadInputTypeDatePicker(inputTypeDate)
                            }
                        case Int16(MessageInputType.MessageInputTypeTime.rawValue):
                            if let inputTypeTime = inputObject as? InputTime{
                                self.loadInputTypeDatePicker(inputTypeTime)
                            }
                        case Int16(MessageInputType.MessageInputTypeAddress.rawValue):
                            if let inputTypeAddress = inputObject as? InputAddress{
                                self.loadInputTypeMedia(inputTypeAddress)
                            }
                        case Int16(MessageInputType.MessageInputTypeLocation.rawValue):
                            if let inputTypeLocation = inputObject as? InputLocation{
                                self.loadInputTypeMedia(inputTypeLocation)
                            }
                        case Int16(MessageInputType.MessageInputTypeGetStarted.rawValue):
                            self.inputTextView?.removeFromSuperview()
                            self.loadInputTypeMedia(inputObject)
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
    
    func loadInputTypeText(_ messageObject : Message){
        self.inputTextView = CommonUtility.getFrameworkBundle().loadNibNamed("InputTextFieldView", owner: self, options: nil)?[0] as? InputTextFieldView
        self.inputTextView.configure(messageObject: messageObject)
        self.inputTextView.delegate = self
        self.textContainerView.addSubview(self.inputTextView!)
        self.inputTextView.translatesAutoresizingMaskIntoConstraints = false
        
        self.textContainerView.layer.masksToBounds = false
        self.textContainerView.layer.shadowOffset = CGSize(width : 0, height : -2)
        self.textContainerView.layer.shadowRadius = 2
        self.textContainerView.layer.shadowOpacity = 1.0
        self.textContainerView.layer.shadowColor = UIColor.init(hexString: "#6E6E6E").withAlphaComponent(0.15).cgColor

        ConstraintsHelper.addConstraints(0, trailing: 0, top: 0, height: CGFloat(CellHeights.textInputViewHeight), superView: self.textContainerView, subView: self.inputTextView)
        
        self.textContainerViewHeightConstraint.constant = CGFloat(CellHeights.textInputViewHeight)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.0){
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            };
        }
    }
    
    func configureTextViewHeight(_ height: CGFloat){
        if self.inputTextView != nil , self.textContainerView != nil{
            self.textContainerViewHeightConstraint.constant = height
            ConstraintsHelper.updateConstraint(self.textContainerView, subView: self.inputTextView, constraintType: .height, constraintValue: height)
        }
    }

    func removeInputTextView() {
        if self.inputTextView != nil {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.3, animations: {
                    self.inputContainerViewHeightConstraint.constant = 0
                }, completion: { (finished) in
                    self.inputTextView.removeFromSuperview()
                    self.inputTextView = nil
                })
            }
        }
    }
    
    
    func loadInputTypeOptions(_ messageObject : InputTypeOptions){
        self.inputTextView?.removeFromSuperview()
        if messageObject.mandatory == 1{
            self.textContainerViewHeightConstraint.constant = 0
        }else{
            self.inputTextView = CommonUtility.getFrameworkBundle().loadNibNamed("InputTextFieldView", owner: self, options: nil)?[0] as? InputTextFieldView
            self.inputTextView.delegate = self
            self.inputTextView.configure(messageObject: messageObject)
            self.textContainerView.addSubview(self.inputTextView!)
            self.inputTextView.translatesAutoresizingMaskIntoConstraints = false
            
            ConstraintsHelper.addConstraints(0, trailing: 0, top: 0, height: 40, superView: self.textContainerView, subView: self.inputTextView)
            
            self.textContainerViewHeightConstraint.constant = 40
        }
        
        self.inputOptionsView = CommonUtility.getFrameworkBundle().loadNibNamed("InputOptionsView", owner: self, options: nil)?[0] as? InputOptionsView
        self.inputOptionsView?.frame = CGRect(x: 0, y: 0, width: Int(UIScreen.main.bounds.size.width), height: CellHeights.optionsViewCellHeight)
        self.inputOptionsView?.frame = self.inputContainerView.bounds
        self.inputOptionsView?.configure(messageObject: messageObject)
        self.inputOptionsView?.backgroundColor = UIColor.clear
        self.inputOptionsView?.delegate = self
        self.inputContainerView.backgroundColor = UIColor.clear
        self.inputContainerView.addSubview(self.inputOptionsView!)
        self.inputContainerViewHeightConstraint.constant = CGFloat(CellHeights.optionsViewCellHeight)

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.0){
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            };
        }
    }
    
    func removeInputTypeOptions() {
        if self.inputOptionsView != nil {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.3, animations: {
                    self.inputContainerViewHeightConstraint.constant = 0
                }, completion: { (finished) in
                    self.inputOptionsView?.removeFromSuperview()
                    self.inputOptionsView = nil
                })
            }
        }
    }
    
    func loadInputTypeMedia(_ messageObject : Input){
        self.inputTextView?.removeFromSuperview()
        if messageObject.mandatory == 1{
            self.textContainerViewHeightConstraint.constant = 0
        }else{
            self.inputTextView = CommonUtility.getFrameworkBundle().loadNibNamed("InputTextFieldView", owner: self, options: nil)?[0] as? InputTextFieldView
            self.inputTextView.delegate = self
            self.inputTextView.configure(messageObject: messageObject)
            self.textContainerView.addSubview(self.inputTextView!)
            self.inputTextView.translatesAutoresizingMaskIntoConstraints = false
            
            ConstraintsHelper.addConstraints(0, trailing: 0, top: 0, height: 40, superView: self.textContainerView, subView: self.inputTextView)
            
            self.textContainerViewHeightConstraint.constant = 40
        }
        
        self.inputTypeButton = CommonUtility.getFrameworkBundle().loadNibNamed("InputTypeButton", owner: self, options: nil)?[0] as? InputTypeButton
        self.inputTypeButton?.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: 80)
        self.inputTypeButton?.frame = self.inputContainerView.bounds
        self.inputTypeButton?.configure(messageObject: messageObject)
        self.inputTypeButton?.backgroundColor = UIColor.clear
        self.inputTypeButton?.delegate = self
        self.inputContainerView.addSubview(self.inputTypeButton!)
        self.inputContainerViewHeightConstraint.constant = 80
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.0){
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            };
        }
    }
    
    func removeInputTypeMedia(){
        if self.inputTypeButton != nil {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.3, animations: {
                    self.inputContainerViewHeightConstraint.constant = 0
                }, completion: { (finished) in
                    self.inputTypeButton?.removeFromSuperview()
                    self.inputTypeButton = nil
                })
            }
        }
    }
    
    func loadInputTypeDatePicker(_ messageObject : Input){
        self.inputTextView?.removeFromSuperview()
        if messageObject.mandatory == 1{
            self.textContainerViewHeightConstraint.constant = 0
        }else{
            self.inputTextView = CommonUtility.getFrameworkBundle().loadNibNamed("InputTextFieldView", owner: self, options: nil)?[0] as? InputTextFieldView
            self.inputTextView.delegate = self
            self.inputTextView.configure(messageObject: messageObject)
            self.textContainerView.addSubview(self.inputTextView!)
            self.inputTextView.translatesAutoresizingMaskIntoConstraints = false
            
            ConstraintsHelper.addConstraints(0, trailing: 0, top: 0, height: 40, superView: self.textContainerView, subView: self.inputTextView)
            
            self.textContainerViewHeightConstraint.constant = 40
        }
        
        self.inputTypeButton = CommonUtility.getFrameworkBundle().loadNibNamed("InputTypeButton", owner: self, options: nil)?[0] as? InputTypeButton
        self.inputTypeButton?.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: 80)
        self.inputTypeButton?.frame = self.inputContainerView.bounds
        self.inputTypeButton?.configure(messageObject: messageObject)
        self.inputTypeButton?.backgroundColor = UIColor.clear
        self.inputTypeButton?.delegate = self
        self.inputContainerView.addSubview(self.inputTypeButton!)
        self.inputContainerViewHeightConstraint.constant = 80
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.0){
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            };
        }
    }
    
    func removeInputTypeDatePicker(){
        if self.inputDatePickerView != nil {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.3, animations: {
                    self.inputContainerViewHeightConstraint.constant = 0
                }, completion: { (finished) in
                    self.inputDatePickerView?.removeFromSuperview()
                    self.inputDatePickerView = nil
                })
            }
        }
    }
    // MARK: -
    // MARK: InputTextFieldViewDelegate Methods
    
    func didTappedOnInputCell(_ inputDict:[String: Any], messageObject: Message?){
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillHide, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyBoardWillShow(withNotification:)), name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyBoardWillHide(withNotification:)), name: .UIKeyboardWillHide, object: nil)
        
        self.inputContainerViewHeightConstraint.constant = 0
        self.textContainerViewHeightConstraint.constant = 0
        self.view.endEditing(true)
        self.clearInputSubViews()
        self.syncInputMessageToServer(inputDict, messageObject: messageObject)
    }
    
    func didTappedOnCloseCell(){
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillHide, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyBoardWillShow(withNotification:)), name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyBoardWillHide(withNotification:)), name: .UIKeyboardWillHide, object: nil)
    }

    
    func clearInputSubViews(){
        self.textContainerView.subviews.forEach { $0.removeFromSuperview() }
        self.inputContainerView.subviews.forEach { $0.removeFromSuperview() }
    }
   
    func  syncInputMessageToServer(_ inputDict:[String: Any], messageObject: Message?) {
        var requestDict = [String: Any]()
        if let messageObject = messageObject{
            requestDict = RequestHelper.getRequestDictionary(messageObject, inputDict: inputDict)
            if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                if var metaInfo = requestDict["meta"] as? [String: Any]{
                    metaInfo[Constants.kResponseToKey] = lastObject.messageId
                    metaInfo[Constants.kTimeStampKey] = NSNumber(value : Date().millisecondsSince1970)
                    requestDict["meta"] = metaInfo
                }
            }
        }else{
            if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                requestDict = RequestHelper.getRequestDictionaryForEmptyMessageObject(lastObject, inputDict: inputDict)
                if var metaInfo = requestDict["meta"] as? [String: Any]{
                    metaInfo[Constants.kResponseToKey] = lastObject.messageId
                    metaInfo[Constants.kTimeStampKey] = NSNumber(value : Date().millisecondsSince1970)
                    requestDict["meta"] = metaInfo
                }
            }

        }
        print(requestDict)
        print(inputDict)
        if messageObject is Carousel{
            dataHelper.updateCarouselDBMessage(params: requestDict, successBlock: { (messageObject) in
                self.reloadLastPreviousCell()
                self.scrollToTableBottom()
                self.dataHelper.sendMessageToServer(params: requestDict, apiPath: nil, messageObject: messageObject, completionHandler: { (response) in
                    
                })
            })
        }else{
            dataHelper.updateInputDBMessage(params: requestDict, successBlock: { (messageObject) in
                self.reloadLastPreviousCell()
                self.scrollToTableBottom()
                self.dataHelper.sendMessageToServer(params: requestDict, apiPath: nil, messageObject: messageObject, completionHandler: { (response) in
                })
            })
        }
    }
    
    func didTappedOnMediaCell(_ messageObject: Message){
 
        if let inputTypeMedia = messageObject as? InputTypeMedia{
            switch inputTypeMedia.mediaType {
            case Int16(MessageSimpleType.MessageSimpleTypeImage.rawValue):
                let imagePickerAlert = UIAlertController(title: nil, message: "Choose your source", preferredStyle: UIAlertControllerStyle.actionSheet)
                
                imagePickerAlert.addAction(UIAlertAction(title: "Camera", style: UIAlertActionStyle.default) { (result : UIAlertAction) -> Void in
                    let picker = UIImagePickerController()
                    picker.delegate = self
                    picker.sourceType = .camera
                    picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)!
                    self.present(picker, animated: true, completion: nil)
                    
                })
                imagePickerAlert.addAction(UIAlertAction(title: "Photo library", style: UIAlertActionStyle.default) { (result : UIAlertAction) -> Void in
                    let picker = UIImagePickerController()
                    picker.delegate = self
                    picker.sourceType = .photoLibrary
                    self.present(picker, animated: true, completion: nil)
                })
                self.present(imagePickerAlert, animated: true, completion: nil)

            case Int16(MessageSimpleType.MessageSimpleTypeVideo.rawValue):
                let imagePickerAlert = UIAlertController(title: nil, message: "Choose your source", preferredStyle: UIAlertControllerStyle.actionSheet)
                
                imagePickerAlert.addAction(UIAlertAction(title: "Video", style: UIAlertActionStyle.default) { (result : UIAlertAction) -> Void in
                    let picker = UIImagePickerController()
                    picker.delegate = self
                    picker.mediaTypes = ["public.movie"]
                    picker.sourceType = .camera
                    picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)!
                    self.present(picker, animated: true, completion: nil)
                    
                })
                imagePickerAlert.addAction(UIAlertAction(title: "Video library", style: UIAlertActionStyle.default) { (result : UIAlertAction) -> Void in
                    let picker = UIImagePickerController()
                    picker.delegate = self
                    picker.sourceType = .photoLibrary
                    picker.mediaTypes = ["public.movie"]
                    self.present(picker, animated: true, completion: nil)
                })
                self.present(imagePickerAlert, animated: true, completion: nil)

            default:
                break
            }
        }
    }
    
    // MARK: -
    // MARK: UIDocumentPicker Methods
    
    func didTappedOnUploadFile(_ messageObject: Message){
        let d = UIDocumentMenuViewController(documentTypes: ["public.item" as String], in: .import)
        d.delegate = self
        self.present(d, animated: true, completion: nil)
    }
    
    
    public func documentMenu(_ documentMenu: UIDocumentMenuViewController, didPickDocumentPicker documentPicker: UIDocumentPickerViewController){
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        if controller.documentPickerMode == UIDocumentPickerMode.import {
            if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                if lastObject.messageType == 2{
                    if let inputObject = lastObject as? Input{
                        if inputObject.inputInfo == nil{
                            switch inputObject.inputType{
                            case Int16(MessageInputType.MessageInputTypeMedia.rawValue):
                                APIManager.sharedInstance.uploadMedia(withMedia: url as URL, completionHandler: { (response) in
                                    if let links = response["links"] as? NSArray{
                                        if links.count > 0 {
                                            let linksInfo = links.object(at: 0) as? NSDictionary
                                            let mediaInfo = [Constants.kUrlKey : linksInfo!["href"], Constants.kTypeKey : NSNumber(value:3)]
                                            let inputDict = [Constants.kInputKey: [Constants.kMediaKey: [mediaInfo]]]
                                            DispatchQueue.main.async {
                                                self.clearInputSubViews()
                                            }
                                            self.syncInputMessageToServer(inputDict, messageObject: lastObject)
                                        }
                                    }
                                })
                            default:
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]){
        print("The Url is : /(cico)")
        
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("we cancelled")
        dismiss(animated: true, completion: nil)
        
        
    }

    
    func didTappedOnAddressCell(_ messageObject: Message){
        if let inputTypeAddress = messageObject as? InputAddress{
            print("show address")
            NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillShow, object: nil)
            NotificationCenter.default.removeObserver(self, name: .UIKeyboardWillHide, object: nil)
            
            let addressView =  CommonUtility.getFrameworkBundle().loadNibNamed("AddressView", owner: self, options: nil)?[0] as! AddressView
            addressView.delegate = self
            addressView.configure(messageObject: inputTypeAddress)
            addressView.frame = (self.navigationController?.view.bounds)!
            self.navigationController?.view.addSubview(addressView)
        }
    }
    
    func didTappedOnListCell(_ messageObject: Message){
        let listView =  CommonUtility.getFrameworkBundle().loadNibNamed("InputListView", owner: self, options: nil)?[0] as! InputListView
        listView.delegate = self
        listView.configure(messageObject: messageObject as! InputTypeOptions)
        listView.frame = (self.navigationController?.view.bounds)!
        self.navigationController?.view.addSubview(listView)
    }
    
    func didTappedOnSendDateCell(_ messageObject: Message){
        self.inputDatePickerView = CommonUtility.getFrameworkBundle().loadNibNamed("DatePickerView", owner: self, options: nil)?[0] as? DatePickerView
        self.inputDatePickerView?.frame = (self.navigationController?.view.bounds)!
        self.inputDatePickerView?.configure(messageObject: messageObject)
        self.inputDatePickerView?.delegate = self
        self.navigationController?.view.addSubview(self.inputDatePickerView!)
    }

    func didTappedOnGetStartedCell(_ messageObject: Message){
        self.view.endEditing(true)
        self.clearInputSubViews()
        let inputDict = [Constants.kInputKey: [Constants.kInputKey: "Get Started"]]
        self.syncInputMessageToServer(inputDict, messageObject: messageObject)
    }
    
    func didTappedOnSendLocationCell(_ messageObject: Message) {
        if let _ = messageObject as? InputLocation{
            /*
            let config = GMSPlacePickerConfig(viewport: nil)
            let placePicker = GMSPlacePicker(config: config)
            
            placePicker.pickPlace(callback: {(place, error) -> Void in
                if let error = error {
                    print("Pick Place error: \(error.localizedDescription)")
                    return
                }
                if let latitude = place?.coordinate.latitude, let longitude = place?.coordinate.longitude{
                    let actionSheetController: UIAlertController = UIAlertController(title: "Alert", message: "Do you want to share the selected location?", preferredStyle: .alert)
                    let cancelAction: UIAlertAction = UIAlertAction(title: "Cancel", style: .cancel) { action -> Void in
                    }
                    actionSheetController.addAction(cancelAction)
                    
                    let okAction: UIAlertAction = UIAlertAction(title: "Ok", style: .default) { action -> Void in
                        var locationInfo = [String: Any]()
                        
                        locationInfo[Constants.kLatitudeKey] = latitude
                        locationInfo[Constants.kLongitudeKey] = longitude
                        let inputDict = [Constants.kInputKey: ["location": locationInfo]]
                        self.didTappedOnInputCell(inputDict, messageObject: messageObject)
                    }
                    actionSheetController.addAction(okAction)
                    
                    self.present(actionSheetController, animated: true, completion: nil)
                }
            })
             */
        }
    }
    
    func didTappedOnOpenUrl(_ url:String){
        UIApplication.shared.openURL(URL(string: url)!)
    }

    func showAlert(_ alertText:String){
        let actionSheetController: UIAlertController = UIAlertController(title: "Alert", message: alertText, preferredStyle: .alert)
        let cancelAction: UIAlertAction = UIAlertAction(title: "Ok", style: .cancel) { action -> Void in
            //Just dismiss the action sheet
        }
        actionSheetController.addAction(cancelAction)
        
        self.present(actionSheetController, animated: true, completion: nil)
        
        print(alertText)
    }
    
    // MARK: -
    // MARK: KeyBoard Notification Methods
    
    @objc func keyBoardWillShow(withNotification notification : NSNotification)->Void{
        let dic = notification.userInfo
        let duration = dic?["UIKeyboardAnimationDurationUserInfoKey"] as? Double
        let keyPadFrame = dic?["UIKeyboardFrameEndUserInfoKey"] as? CGRect
        
        self.inputTextViewBottomConstraint.constant = (keyPadFrame?.size.height)!
        scrollToTableBottom()

        UIView.animate(withDuration: duration!, delay:0.0, options: UIViewAnimationOptions.allowAnimatedContent, animations: {
            self.view.layoutIfNeeded()
        }) { (_ finished: Bool) in
            if(finished){
            }
        }
    }
    
    @objc func keyBoardWillHide(withNotification notification : NSNotification)->Void{
        let dic = notification.userInfo
        let duration = dic?["UIKeyboardAnimationDurationUserInfoKey"] as? Double
        self.inputTextViewBottomConstraint.constant = 0
        scrollToTableBottom()
        UIView.animate(withDuration: duration!, delay:0.0, options: UIViewAnimationOptions.allowAnimatedContent, animations: {
            self.view.layoutIfNeeded()
        }) { (_ finished: Bool) in
            if(finished){
            }
        }
    }
    
    @objc func notificationReceived(_ notification : NSNotification) {
        if (self.messagesFetchController?.fetchedObjects?.count)! > 0{
            self.reloadLastPreviousCell()
            self.scrollToTableBottom()
            print(self.messagesFetchController?.fetchedObjects?.last ?? Message())
            DispatchQueue.main.async {
                if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                    self.loadInputView(lastObject)
                }
            }
        }
    }
    
    
    func scrollToTableBottom() -> Void
    {
        DispatchQueue.main.async {
            if (self.messagesFetchController?.fetchedObjects?.count)! > 0{
                let indexPath = IndexPath(row: (self.messagesFetchController?.sections?.last?.numberOfObjects)! - 1, section: (self.messagesFetchController?.sections?.count)! - 1)
                UIView.animate(withDuration: 0.25, delay:0.0, options: UIViewAnimationOptions.allowAnimatedContent, animations: {
                    self.tableView.scrollToRow(at: indexPath, at: .none, animated: false)
                }) { (_ finished: Bool) in
                    if(finished){
                    }
                }
            }
        }
        //
        //        let scrollPoint = CGPoint(x: 0, y: self.tableView.contentSize.height - self.tableView.frame.size.height)
        //        self.tableView.setContentOffset(scrollPoint, animated: true)
        //        return
        
        
        //        let contentOffset = rect.size.height + rect.origin.y + 180
        //        let offset = CGPoint.init(x: 0, y: contentOffset)
        ////        self.tableView.beginUpdates()
        //        self.tableView.setContentOffset(offset, animated: false)
        ////        self.tableView.endUpdates()
        
        //        self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]){
        /*
        if let videoURL = info[UIImagePickerControllerMediaURL] as? NSURL {
            
            //Create AVAsset from url
            let ass = AVAsset(url:videoURL as URL)
            
            if let videoThumbnail = ass.videoThumbnail{
                print("Success")
            }
        }
        */
        let mediaType = info[UIImagePickerControllerMediaType] as! NSString
        if mediaType.hasSuffix(".movie"){
            if let videoPathUrl = info[UIImagePickerControllerMediaURL] as? NSURL {
                if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                    if lastObject.messageType == 2{
                        if let inputObject = lastObject as? Input{
                            if inputObject.inputInfo == nil{
                                switch inputObject.inputType{
                                case Int16(MessageInputType.MessageInputTypeMedia.rawValue):
                                    APIManager.sharedInstance.uploadMedia(withMedia: videoPathUrl as URL, completionHandler: { (response) in
                                        if let links = response["links"] as? NSArray{
                                            if links.count > 0 {
                                                let linksInfo = links.object(at: 0) as? NSDictionary
                                                let mediaInfo = [Constants.kUrlKey : linksInfo!["href"], Constants.kTypeKey : NSNumber(value:2)]
                                                let inputDict = [Constants.kInputKey: [Constants.kMediaKey: [mediaInfo]]]
                                                    DispatchQueue.main.async {
                                                        self.clearInputSubViews()
                                                    }
                                                    self.syncInputMessageToServer(inputDict, messageObject: lastObject)
                                            }
                                        }
                                    })
                                default:
                                    break
                                }
                            }
                        }
                    }
                }
                
            }

//            APIManager.sharedInstance.uploadMedia(withMedia: videoPathUrl! as URL, completionHandler: { (response) in
//                print(response)
//            })
//            print(videoPathUrl ?? NSURL())
        }else if  mediaType.hasSuffix(".image"){
            if let pickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
                if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
                    if lastObject.messageType == 2{
                        if let inputObject = lastObject as? Input{
                            if inputObject.inputInfo == nil{
                                switch inputObject.inputType{
                                case Int16(MessageInputType.MessageInputTypeMedia.rawValue):
                                    APIManager.sharedInstance.uploadImage(withMedia: pickedImage, completionHandler: { (response) in
                                        if let links = response["links"] as? NSArray{
                                            if links.count > 0 {
                                                let linksInfo = links.object(at: 0) as? NSDictionary
                                                let mediaInfo = [Constants.kUrlKey : linksInfo!["href"], Constants.kTypeKey : NSNumber(value:0)]
                                                
                                                let inputDict = [Constants.kInputKey: [Constants.kMediaKey: [mediaInfo]]]
                                                DispatchQueue.main.async {
                                                    self.clearInputSubViews()
                                                }
                                                self.syncInputMessageToServer(inputDict, messageObject: lastObject)
                                            }
                                        }
                                    })
                                default:
                                    break
                                }
                            }
                        }
                    }
                }
              
            }
        }
        self.dismiss(animated: true, completion: nil)
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController){
        self.dismiss(animated: true, completion: nil)
    }

    func reloadLastPreviousCell(){
        if (self.messagesFetchController?.fetchedObjects?.count)! > 1{
            let _ = NSIndexPath(row: (self.messagesFetchController?.sections?.last?.numberOfObjects)! - 2, section: (self.messagesFetchController?.sections?.count)! - 1)
            self.tableView.reloadData()
//            self.tableView.reloadRows(at: [previousIndexPath as IndexPath], with: .none)
        }
    }
    
    func playVideo (view: UIViewController , mediaUrl : String) {
        let player = AVPlayer(url: URL.init(string: mediaUrl)!)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        view.present(playerViewController, animated: true) {
            playerViewController.player!.play()
        }
    }

    
    /*
    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController)
    {
        self.dismiss(animated: true, completion: nil)
    }
    
    func mediaPicker(mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
        //run any code you want once the user has picked their chosen audio
    }

    @IBAction func imageTapped(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.allowsEditing = true
        
        present(picker, animated: true, completion: nil)
        
        print("image tapped")
    }
   
    @IBAction func photoTapped(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = true
        
        present(picker, animated: true, completion: nil)
        
        print("photo tapped")
    }
    
    @IBAction func audioTapped(_ sender: Any) {
        let picker = MPMediaPickerController(mediaTypes: .anyAudio)
        picker.delegate = self
        picker.allowsPickingMultipleItems = false
        picker.prompt = NSLocalizedString("Chose audio file", comment: "Please chose an audio file")
        self.present(picker, animated: true, completion: nil)
        
        print("audio tapped")
    }
    
    @IBAction func videoTapped(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.delegate = self
        picker.allowsEditing = true
        
        present(picker, animated: true, completion: nil)
        
        
        print("video tapped")
    }
    
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]){
        
        if let videoURL = info[UIImagePickerControllerMediaURL] as? NSURL {
            
            //Create AVAsset from url
            let ass = AVAsset(url:videoURL as URL)
            
            if let videoThumbnail = ass.videoThumbnail{
                print("Success")
            }
        }
        
        let mediaType = info[UIImagePickerControllerMediaType] as! NSString
        if mediaType.hasSuffix(".movie"){
            let videoPathUrl = info[UIImagePickerControllerMediaURL] as? NSURL
            APIManager.sharedInstance.uploadMedia(withMedia: videoPathUrl! as URL, completionHandler: { (response) in
                print(response)
            })
            print(videoPathUrl ?? NSURL())
        }else if  mediaType.hasSuffix(".image"){
            print(info[UIImagePickerControllerMediaURL] ?? NSURL())
            if let pickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
                APIManager.sharedInstance.uploadImage(withMedia: pickedImage, completionHandler: { (response) in
                    print(response)
                })
            }
        }
        self.dismiss(animated: true, completion: nil)
    }
    
    func saveVideoWithURLPath(_ videoPathUrl:NSURL){
        var localId:String?

        PHPhotoLibrary.shared().performChanges({
            let request =  PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoPathUrl as URL)
            localId = request?.placeholderForCreatedAsset?.localIdentifier

        }) { saved, error in
            if saved {
                DispatchQueue.main.async(execute: { () -> Void in
                    
                    if let localId = localId {
                        
                        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
                        let assets = result.objects(at: NSIndexSet(indexesIn: NSRange(location: 0, length: result.count)) as IndexSet)
                        
                        if let asset = assets.first {
                            print(asset as PHAsset)
                            self.playVideo(view: self, videoAsset: asset)
                            // Do something with result
                        }
                    }
                })
            }
        }
    }
    
    func saveVideoFromURL(urlString:NSString){
        var localId:String?

//        urlString = "http://www.sample-videos.com/video/mp4/720/big_buck_bunny_720p_1mb.mp4"
        DispatchQueue.global(qos: .background).async {
            if let url = URL(string: "http://www.sample-videos.com/video/mp4/720/big_buck_bunny_720p_1mb.mp4" as String),
                let urlData = NSData(contentsOf: url)
            {
                let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0];
                let filePath="\(documentsPath)/tempFile.mp4";
                DispatchQueue.main.async {
                    urlData.write(toFile: filePath, atomically: true)
                    PHPhotoLibrary.shared().performChanges({
                        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: filePath))
                        localId = request?.placeholderForCreatedAsset?.localIdentifier

                    }) { completed, error in
                        if completed {
                            
                            let fetchOptions = PHFetchOptions()
                            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                            
                            // After uploading we fetch the PHAsset for most recent video and then get its current location url
                            
                            let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions).lastObject
                            PHImageManager().requestAVAsset(forVideo: fetchResult!, options: nil, resultHandler: { (avurlAsset, audioMix, dict) in
                                let newObj = avurlAsset as! AVURLAsset
                                print(newObj.url)
                                DispatchQueue.main.async {
                                    let player = AVPlayer(url: newObj.url)
                                    let playerViewController = AVPlayerViewController()
                                    playerViewController.player = player
                                    self.present(playerViewController, animated: true) {
                                        playerViewController.player!.play()
                                    }
                                }
                                // This is the URL we need now to access the video from gallery directly.
                            })
//
//                            DispatchQueue.main.async(execute: { () -> Void in
//                                
//                                if let localId = localId {
//                                    
//                                    let result = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
//                                    let assets = result.objects(at: NSIndexSet(indexesIn: NSRange(location: 0, length: result.count)) as IndexSet)
//                                    
//                                    if let asset = assets.first {
//                                        print(asset as PHAsset)
//                                        self.playVideo(view: self, videoAsset: asset)
//                                        // Do something with result
//                                    }
//                                }
//                            })
                        }
                    }
                }
            }
        }
    }
    
    func saveImageFromURL(urlString:NSString){
        var localId:String?
        
        //        urlString = "http://www.sample-videos.com/video/mp4/720/big_buck_bunny_720p_1mb.mp4"
        DispatchQueue.global(qos: .background).async {
            if let url = URL(string: "http://i2.cdn.cnn.com/cnnnext/dam/assets/161217142430-2017-cars-ferrari-1-overlay-tease.jpg" as String),
                let urlData = NSData(contentsOf: url)
            {
                let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0];
                let filePath="\(documentsPath)/tempFile.jpg";
                DispatchQueue.main.async {
                    urlData.write(toFile: filePath, atomically: true)
                    PHPhotoLibrary.shared().performChanges({
                        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: filePath))
                        localId = request?.placeholderForCreatedAsset?.localIdentifier
                        
                    }) { completed, error in
                        if completed {
                            DispatchQueue.main.async(execute: { () -> Void in
                                
                                if let localId = localId {
                                    
                                    let result = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
                                    let assets = result.objects(at: NSIndexSet(indexesIn: NSRange(location: 0, length: result.count)) as IndexSet)
                                    
                                    if let asset = assets.first {
                                        print(asset as PHAsset)
                                        self.playVideo(view: self, videoAsset: asset)
                                    }
                                }
                            })
                        }
                    }
                }
            }
        }
    }
    
    func playVideo (view: UIViewController, videoAsset: PHAsset) {
     
        guard (videoAsset.mediaType == .video) else {
            print("Not a valid video media type")
            return
        }
     
        PHCachingImageManager().requestAVAsset(forVideo: videoAsset, options: nil) { (asset, audioMix, args) in
            let asset = asset as! AVURLAsset
     
            DispatchQueue.main.async {
                let player = AVPlayer(url: asset.url)
                let playerViewController = AVPlayerViewController()
                playerViewController.player = player
                view.present(playerViewController, animated: true) {
                    playerViewController.player!.play()
                }
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController){
        self.dismiss(animated: true, completion: nil)
    }

       func didTappedOnTextCell(_ inputDict:[String: Any], messageObject: Message){
        var requestDict = RequestHelper.getRequestDictionary(messageObject, inputDict: inputDict)
        if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
            if var metaInfo = requestDict["meta"] as? [String: Any]{
                metaInfo[Constants.kResponseToKey] = lastObject.messageId
                metaInfo[Constants.kTimeStampKey] = NSNumber(value : Date().millisecondsSince1970)
                requestDict["meta"] = metaInfo
            }
        }
        print(requestDict)
        print(inputDict)
        
        dataHelper.updateDBMessage(params: requestDict, successBlock: { (messageObject) in
            self.reloadLastPreviousCell()
            self.dataHelper.sendMessageToServer(params: requestDict, apiPath: nil, messageObject: messageObject, completionHandler: { (response) in
                self.reloadLastPreviousCell()
                self.scrollToTableBottom()
            })
        })
        //        self.removeInputTextView()
    }
    
    // MARK: -
    //MARK: ButtonsViewDelegate Methods
    func didTappedOnOptionsCell(_ inputDict:[String: Any], messageObject: Message){
        var requestDict = RequestHelper.getRequestDictionary(messageObject, inputDict: inputDict)
        if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
            if var metaInfo = requestDict["meta"] as? [String: Any]{
                metaInfo[Constants.kResponseToKey] = lastObject.messageId
                metaInfo[Constants.kTimeStampKey] = NSNumber(value : Date().millisecondsSince1970)
                requestDict["meta"] = metaInfo
            }
        }
        print(requestDict)
        print(inputDict)
        
        dataHelper.updateDBMessage(params: requestDict, successBlock: { (messageObject) in
            self.dataHelper.sendMessageToServer(params: requestDict, apiPath: nil, messageObject: messageObject, completionHandler: { (response) in
                self.reloadLastPreviousCell()
                self.scrollToTableBottom()
            })
        })
        //        self.removeInputTypeOptions()
    }
    func didTappedOnListCell(_ inputDict:[String: Any], messageObject: Message){
        var requestDict = RequestHelper.getRequestDictionary(messageObject, inputDict: inputDict)
        if let lastObject = self.messagesFetchController?.fetchedObjects?.last{
            if var metaInfo = requestDict["meta"] as? [String: Any]{
                metaInfo[Constants.kResponseToKey] = lastObject.messageId
                metaInfo[Constants.kTimeStampKey] = NSNumber(value : Date().millisecondsSince1970)
                requestDict["meta"] = metaInfo
            }
        }
        print(requestDict)
        print(inputDict)
        
        dataHelper.updateDBMessage(params: requestDict, successBlock: { (messageObject) in
            self.dataHelper.sendMessageToServer(params: requestDict, apiPath: nil, messageObject: messageObject, completionHandler: { (response) in
                self.reloadLastPreviousCell()
                self.scrollToTableBottom()
            })
        })
        print(requestDict)
    }
     */
    ///  IMAGE ZOOM
    
    func imageTap(imageView: UIImageView)
    {
        // handling code
        
        let zoomView = UIView()
        zoomView.frame = CGRect(x: 0, y: 0, width: DeviceUtils.ScreenSize.SCREEN_WIDTH, height: DeviceUtils.ScreenSize.SCREEN_HEIGHT)
        zoomView.backgroundColor = UIColor(white: 0, alpha: 0.8)
        view.addSubview(zoomView)
        
        let cancelButton = UIButton(type: .custom)
        cancelButton.frame = CGRect(x: zoomView.frame.maxX - 50, y: 25, width: 45, height: 45)
        cancelButton.addTarget(self, action: #selector(self.dismissImage), for: .touchDown)
        cancelButton.setImage(UIImage(named: "closeButton"), for: .normal)
        cancelButton.backgroundColor = UIColor.clear
        zoomView.addSubview(cancelButton)
        
        let zoomScrollView = UIScrollView()
        zoomScrollView.frame = CGRect(x: 0, y: 0, width: zoomView.frame.width, height: zoomView.frame.height)
        zoomScrollView.backgroundColor = UIColor.clear
        zoomScrollView.minimumZoomScale = 0.5
        zoomScrollView.maximumZoomScale = 3.0
        zoomScrollView.delegate = self
        zoomScrollView.alwaysBounceVertical = true
        zoomScrollView.alwaysBounceHorizontal = true
        zoomView.addSubview(zoomScrollView)
        
        let imageHeight: CGFloat = scaleImageAutoLayout(imageView, withWidth: DeviceUtils.ScreenSize.SCREEN_WIDTH)
        let zoomImg = UIImageView()
        zoomImg.frame = CGRect(x: 0, y: (self.view.frame.height - imageHeight) / 2, width: DeviceUtils.ScreenSize.SCREEN_WIDTH, height: imageHeight)
        zoomImg.backgroundColor = UIColor.clear
        zoomImg.image = imageView.image
        zoomImg.contentMode = .scaleAspectFit
        zoomImg.tag = 25
        zoomScrollView.addSubview(zoomImg)
        zoomScrollView.contentSize = zoomImg.frame.size
        zoomView.bringSubview(toFront: cancelButton)
        //
        
        centerScrollViewContents(zoomScrollView)
    }
    
    @objc func dismissImage(sender: UIButton){
        let contentView = sender.superview
        contentView?.removeFromSuperview()
    }
    
    func scaleImageAutoLayout(_ imageView: UIImageView, withWidth width: CGFloat) -> CGFloat{
        let scale: CGFloat = width / imageView.image!.size.width
        let height: CGFloat = imageView.image!.size.height * scale
        
        return height
    }

    public func viewForZooming(in delgateScrollView: UIScrollView) -> UIView?{
        return delgateScrollView.viewWithTag(25) as? UIImageView
    }

    public func scrollViewDidZoom(_ delgateScrollView: UIScrollView)    {
        centerScrollViewContents(delgateScrollView)
    }
    
    func centerScrollViewContents(_ scroller: UIScrollView)
    {
        let boundsSize: CGSize = scroller.bounds.size
        let imgVi = scroller.viewWithTag(25) as? UIImageView
        var contentsFrame: CGRect? = imgVi?.frame
        if (imgVi?.frame.size.width)! < boundsSize.width {
            contentsFrame?.origin.x = (boundsSize.width - (imgVi?.frame.size.width)!) / 2.0
        }
        else {
            contentsFrame?.origin.x = 0.0
        }
        if (imgVi?.frame.size.height)! < boundsSize.height {
            contentsFrame?.origin.y = (boundsSize.height - (imgVi?.frame.size.height)!) / 2.0
        }
        else {
            contentsFrame?.origin.y = 0.0
        }
        imgVi?.frame = contentsFrame!
    }
}