import UIKit

class QuestionsViewController: UIViewController {

	// MARK: Properties
	
	@IBOutlet weak var answerStub: RoundedButton!
	
	var answerButtons: [RoundedButton] = []
	
	@IBOutlet weak var pauseButton: UIButton!
	@IBOutlet weak var remainingQuestionsLabel: UILabel!
	
	
	@IBOutlet weak var questionLabel: UILabel!
	@IBOutlet weak var questionImageButton: UIButton!
	@IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
	@IBOutlet weak var answersStackView: UIStackView!
	
	@IBOutlet weak var pauseView: UIView!
	@IBOutlet weak var goBack: UIButton!
	@IBOutlet weak var muteMusic: UIButton!
	@IBOutlet weak var mainMenu: UIButton!
	
	@IBOutlet weak var helpButton: UIButton!
	
	@IBOutlet weak var blurView: UIVisualEffectView!
	
	let oldScore = UserDefaultsManager.score
	var correctAnswer: Set<UInt8> = []
	var correctAnswers = Int()
	var incorrectAnswers = Int()
	var repeatTimes = UInt8()
	var currentTopicIndex = Int()
	var currentSetIndex = Int()
	var isSetFromJSON = false
	var set: [QuestionType] = []
	var quiz: EnumeratedIterator<IndexingIterator<Array<QuestionType>>>!
	
	// MARK: View life cycle

	override func viewDidLoad() {
		
		super.viewDidLoad()
		
		self.questionImageButton.setImage(nil, for: .normal)
		self.questionImageButton.imageView?.contentMode = .scaleAspectFill
		self.questionImageButton.imageView?.clipsToBounds = true
		self.questionImageButton.clipsToBounds = true
		self.questionImageButton.layer.cornerRadius = 10
		
		if !self.isSetFromJSON {
			self.setUpQuiz()
		} else {
			self.goBack.isHidden = true
			self.set.shuffle()
			self.quiz = set.enumerated().makeIterator()
		}
		
		DispatchQueue.global(qos: .userInitiated).async {
			self.preloadImages()
		}
		
		self.createAnswerButtons()
		
		let title = AudioSounds.bgMusic?.isPlaying == true ? "Pause music" : "Play music"
		self.muteMusic.setTitle(title.localized, for: .normal)
	
		self.goBack.setTitle("Questions menu".localized, for: .normal)
		self.mainMenu.setTitle("Main menu".localized, for: .normal)
		self.pauseButton.setTitle("Pause".localized, for: .normal)
		self.pauseView.isHidden = true
		self.blurView.isHidden = true
		
		// Theme settings
		self.loadCurrentTheme()
		
		// Loads the theme if user uses a home quick action
		NotificationCenter.default.addObserver(self, selector: #selector(loadCurrentTheme), name: .UIApplicationDidBecomeActive, object: nil)
		
		if UserDefaultsManager.score < 5 {
			self.helpButton.alpha = 0.4
		}
		
		self.addSwipeGestures()
		
		self.pickQuestion()
	}
	
	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		// Redraw the buttons to update the rounded corners when rotating the device
		self.answerButtons.forEach { $0.setNeedsDisplay() }
		self.pauseButton.setNeedsDisplay()
		self.pauseView.setNeedsDisplay()
		self.mainMenu.setNeedsDisplay()
		self.goBack.setNeedsDisplay()
		self.muteMusic.setNeedsDisplay()
	}
	
	// MARK: UIResponder

	// If user shake the device, an alert to repeat the quiz pop ups
	override func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
		
		guard motion == .motionShake else { return }
		
		let currentQuestion = Int(String(remainingQuestionsLabel.text?.first ?? "0")) ?? 0
		
		FeedbackGenerator.impactOcurredWith(style: .medium)
		
		if repeatTimes < 2 && currentQuestion > 1 {
			
			let alertViewController = UIAlertController(title: "Repeat?".localized,
														message: "Do you want to start again?".localized,
														preferredStyle: .alert)
			
			alertViewController.addAction(title: "OK".localized, style: .default) { action in self.repeatActionDetailed() }
			alertViewController.addAction(title: "Cancel".localized, style: .cancel)
			
			present(alertViewController, animated: true)
		}
		else if repeatTimes >= 2 {
			showOKAlertWith(title: "Attention", message: "Maximum help tries per question reached")
		}
	}
	
	// MARK: UIViewController
	
	override var preferredStatusBarStyle: UIStatusBarStyle {
		return .themeStyle(dark: .lightContent, light: .default)
	}

	// MARK: UIStoryboardSegue Handling
	
	@IBAction func unwindToQuestions(_ segue: UIStoryboardSegue) { }
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "unwindToQRScanner" {
			AudioSounds.bgMusic?.setVolumeLevel(to: AudioSounds.bgMusicVolume)
		}
		else if segue.identifier == "imageDetailsSegue", let imageDetailsVC = segue.destination as? ImageDetailsViewController {
			imageDetailsVC.modalPresentationStyle = .overCurrentContext
			imageDetailsVC.viewDidLoad()
			imageDetailsVC.imageView?.image = self.questionImageButton.imageView?.image
			imageDetailsVC.closeViewButton?.backgroundColor = .themeStyle(dark: .orange, light: .coolBlue)
			//imageDetailsVC.closeViewButton?.isHidden = true
			imageDetailsVC.preferredContentSize = imageDetailsVC.imageView?.sizeThatFits(self.view.frame.size) ?? imageDetailsVC.view.frame.size
			
			/*if let validCloseButton = imageDetailsVC.closeViewButton {
				UIView.transition(with: validCloseButton, duration: 0, options: [.transitionCrossDissolve], animations: {}, completion: { completed in
					if completed {
						validCloseButton.isHidden = false
					}
				})
			}*/
		}
	}
	
	// MARK: Actions
	
	@IBAction func tapAnyWhereToClosePauseMenu(_ sender: UITapGestureRecognizer) {
		if !pauseView.isHidden {
			self.pauseMenuAction()
		}
	}
	
	@objc func verifyButton(_ sender: RoundedButton) {
		self.verify(answer: UInt8(sender.tag))
	}

	@IBAction func pauseMenu() {
		self.pauseMenuAction()
	}
	
	@IBAction func goBackAction() {
		if !self.isSetFromJSON {
			performSegue(withIdentifier: "unwindToQuizSelector", sender: self)
		} else {
			performSegue(withIdentifier: "unwindToQRScanner", sender: self)
		}
	}
	
	@IBAction func helpAction() {
		
		FeedbackGenerator.impactOcurredWith(style: .light)
		
		if UserDefaultsManager.score < 5 {
			showOKAlertWith(title: "Attention", message: "Not enough points (5 needed)")
		}
		else {
			
			var timesUsed: UInt8 = 0
			answerButtons.forEach { if $0.alpha != 1.0 { timesUsed += 1 } }
			
			if timesUsed < 2 {
				
				UserDefaultsManager.score -= 5

				var randomQuestionIndex = UInt32()
				
				repeat {
					randomQuestionIndex = arc4random_uniform(4)
				} while(self.correctAnswer.contains(UInt8(randomQuestionIndex)) || (answerButtons[Int(randomQuestionIndex)].alpha != 1.0))
				
				UIView.animate(withDuration: 0.4) {
					
					self.answerButtons[Int(randomQuestionIndex)].alpha = 0.4
					
					if (UserDefaultsManager.score < 5) || (timesUsed == 1) {
						self.helpButton.alpha = 0.4
					}
				}
			}
			else {
				showOKAlertWith(title: "Attention", message: "Maximum help tries per question reached")
			}
		}
	}
	
	@IBAction func muteMusicAction() {
		
		if let bgMusic = AudioSounds.bgMusic {
			
			if bgMusic.isPlaying {
				bgMusic.pause()
				muteMusic.setTitle("Play music".localized, for: .normal)
			}
			else {
				bgMusic.play()
				muteMusic.setTitle("Pause music".localized, for: .normal)
			}
			UserDefaultsManager.backgroundMusicSwitchIsOn = bgMusic.isPlaying
		}
	}
	
	@IBAction func respondToSwipeGesture(gesture: UIGestureRecognizer) {
		
		if let swipeGesture = gesture as? UISwipeGestureRecognizer {
			
			let darkThemeEnabled = UserDefaultsManager.darkThemeSwitchIsOn
			
			if !darkThemeEnabled && (swipeGesture.direction == .down) {
				UserDefaultsManager.darkThemeSwitchIsOn = true
				AppDelegate.updateVolumeBarTheme()
			}
			else if darkThemeEnabled && (swipeGesture.direction == .up) {
				UserDefaultsManager.darkThemeSwitchIsOn = false
				AppDelegate.updateVolumeBarTheme()
			}
			else { return }
			
			UIView.transition(with: self.view, duration: 0.3, options: [.curveLinear], animations: {
				self.loadCurrentTheme()
				self.setNeedsStatusBarAppearanceUpdate()
			})
		}
	}
	
	// MARK: Convenience
	
	private func createAnswerButtons() {
		
		// Should fix this stuff in the storyboard...
		self.answerStub.isHidden = true
		
		let numberOfAnswers = set.first?.answers.count ?? 4
		
		for i in 0..<numberOfAnswers {
			
			let button = RoundedButton()
			button.cornerRadius = 15
			button.setup(shadows:
				ShadowEffect(
					shadowColor: .black,
					shadowOffset: CGSize(width: 0.5, height: 3.5),
					shadowOpacity: 0.15,
					shadowRadius: 4)
			)
			button.tag = i
			button.addTarget(self, action: #selector(self.verifyButton), for: .touchDown)
			button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
			
			self.answerButtons.append(button)
			self.answersStackView.addArrangedSubview(button)
		}
	}
	
	private func preloadImages() {
		for fullQuestion in self.set.dropFirst() { //.dropFirst() Drops the first because it will be cached by the 'pickQuestion()' function
			if let validImageURL = fullQuestion.imageURL, !validImageURL.isEmpty && !DataStore.shared.cachedImages.keys.contains(validImageURL.hash) {
				if let validImage = UIImage(contentsOf: URL(string: validImageURL)) {
					DataStore.shared.saveAsCache(image: validImage, withKey: validImageURL.hash)
				}
			}
		}
	}
	
	private func pauseMenuAction(animated: Bool = true) {
		
		let duration: TimeInterval = animated ? 0.1 : 0.0
		let title = (pauseView.isHidden) ? "Continue" : "Pause"
		pauseButton.setTitle(title.localized, for: .normal)
		
		UIView.transition(with: self.view, duration: duration, options: [.transitionCrossDissolve], animations: {
			self.pauseView.isHidden = !self.pauseView.isHidden
			self.blurView.isHidden = !self.blurView.isHidden
		})
		
		let newVolume = (pauseView.isHidden) ? AudioSounds.bgMusicVolume : (AudioSounds.bgMusicVolume / 5.0)
		AudioSounds.bgMusic?.setVolumeLevel(to: newVolume)
	}
	
	private func shuffledQuiz(_ name: Quiz) -> NSArray{
		if currentSetIndex < name.topic.count {
			return name.topic[currentSetIndex].shuffled() as NSArray
		}
		return NSArray()
	}
	
	private func addSwipeGestures() {
		
		let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture))
		swipeUp.direction = .up
		swipeUp.numberOfTouchesRequired = 2
		view.addGestureRecognizer(swipeUp)
		
		let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture))
		swipeDown.direction = .down
		swipeDown.numberOfTouchesRequired = 2
		view.addGestureRecognizer(swipeDown)
	}
	
	@objc func loadCurrentTheme() {
		
		let currentThemeColor = UIColor.themeStyle(dark: .white, light: .black)
		
		self.activityIndicatorView.activityIndicatorViewStyle = UserDefaultsManager.darkThemeSwitchIsOn ? .white : .gray
		self.helpButton.setTitleColor(dark: .orange, light: .defaultTintColor, for: .normal)
		self.remainingQuestionsLabel.textColor = currentThemeColor
		self.questionLabel.textColor = currentThemeColor
		self.view.backgroundColor = .themeStyle(dark: .veryVeryDarkGray, light: .white)
		self.pauseButton.backgroundColor = .themeStyle(dark: .veryDarkGray, light: .veryLightGray)
		self.pauseButton.setTitleColor(dark: .white, light: .defaultTintColor, for: .normal)
		self.pauseView.backgroundColor = .themeStyle(dark: .lightGray, light: .veryVeryLightGray)

		self.pauseView.subviews.first?.subviews.forEach { ($0 as? UIButton)?.setTitleColor(dark: .black, light: .darkGray, for: .normal)
			($0 as? UIButton)?.backgroundColor = .themeStyle(dark: .warmColor, light: .warmYellow) }
		
		self.blurView.effect = UserDefaultsManager.darkThemeSwitchIsOn ? UIBlurEffect(style: .dark) : UIBlurEffect(style: .light)
		
		self.answerButtons.forEach { $0.backgroundColor = .themeStyle(dark: .orange, light: .defaultTintColor); $0.dontInvertColors() }
		
		self.setNeedsStatusBarAppearanceUpdate()
	}
	
	private var currentURL: URL? = nil
	public func pickQuestion() {
		
		// Restore
		UIView.animate(withDuration: 0.75) {
			self.answerButtons.forEach { $0.alpha = 1 }
			
			if UserDefaultsManager.score >= 5 {
				self.helpButton.alpha = 1.0
			}
		}
		
		if let quiz0 = quiz.next() {
			
			let fullQuestion = quiz0.element
			
			self.correctAnswer = fullQuestion.correctAnswers
			self.questionLabel.text = fullQuestion.question.localized
			
			let answers = fullQuestion.answers
			
			for i in 0..<self.answerButtons.count {
				self.answerButtons[i].setTitle(answers[i].localized, for: .normal)
			}
			
			self.remainingQuestionsLabel.text = "\(quiz0.offset + 1)/\(self.set.count)"
			
			self.activityIndicatorView.stopAnimating()
			
			if let imageString = fullQuestion.imageURL, !imageString.isEmpty {
				
				if let cachedImage = DataStore.shared.cachedImage(withKey: imageString.hash) {
					DispatchQueue.main.async {
						self.questionImageButton.setImage(cachedImage, for: .normal)
						self.questionImageButton.isHidden = false
					}
				}
				else {
					
					self.questionImageButton.isHidden = true
					
					self.activityIndicatorView.startAnimating()
					
					self.currentURL = URL(string: imageString)
					
					UIImage.manageContentsOf(self.currentURL, completionHandler: { (image, url) in
						if url == self.currentURL {
							self.activityIndicatorView.stopAnimating()
							self.questionImageButton.setImage(image, for: .normal)
							self.questionImageButton.isHidden = false
						}
						DataStore.shared.saveAsCache(image: image, withKey: imageString.hash)
					}, errorHandler: {
						self.activityIndicatorView.stopAnimating()
					})
				}
			}
			else {
				self.questionImageButton.isHidden = true
			}
		}
		else {
			endOfQuestionsAlert()
		}
	}

	private func isSetCompleted() -> Bool {
		
		let topicName = SetOfTopics.shared.currentTopics[currentTopicIndex].name
		if let topicQuiz = DataStore.shared.completedSets[topicName] {
			return topicQuiz[currentSetIndex] ?? false
		}
		
		return false
	}
	
	private func okActionDetailed() {
		
		if !isSetCompleted() {
			UserDefaultsManager.correctAnswers += correctAnswers
			UserDefaultsManager.incorrectAnswers += incorrectAnswers
			UserDefaultsManager.score += (correctAnswers * 20) - (incorrectAnswers * 10)
		}
		
		let topicName = SetOfTopics.shared.currentTopics[currentTopicIndex].name
		DataStore.shared.completedSets[topicName]?[currentSetIndex] = true
		guard DataStore.shared.save() else { print("Error saving settings"); return }

		if !isSetFromJSON {
			performSegue(withIdentifier: "unwindToQuizSelector", sender: self)
		} else {
			performSegue(withIdentifier: "unwindToMainMenu", sender: self)
		}
	}
	
	private func repeatActionDetailed() {
		self.repeatTimes += 1
		self.correctAnswers = 0
		self.incorrectAnswers = 0
		self.setUpQuiz()
		UserDefaultsManager.score = oldScore
		self.pickQuestion()
	}
	
	@objc private func verify(answer: UInt8) {
		
		pausePreviousSounds()
		
		let isCorrectAnswer = correctAnswer.contains(answer)
		
		if isCorrectAnswer {
			correctAnswers += 1
			AudioSounds.correct?.play()
		}
		else {
			incorrectAnswers += 1
			AudioSounds.incorrect?.play()
		}
		
		UIView.transition(with: self.answerButtons[Int(answer)], duration: 0.25, options: [.transitionCrossDissolve], animations: {
			self.answerButtons[Int(answer)].backgroundColor = isCorrectAnswer ? .darkGreen : .alternativeRed
		}) { completed in
			if completed {
				self.pickQuestion()
				UIView.transition(with: self.answerButtons[Int(answer)], duration: 0.2, options: [.transitionCrossDissolve], animations: {
					self.answerButtons[Int(answer)].backgroundColor = .themeStyle(dark: .orange, light: .defaultTintColor)
				})
			}
		}
		FeedbackGenerator.notificationOcurredOf(type: isCorrectAnswer ? .success : .error)
	}
	
	private func pausePreviousSounds() {
		
		if let incorrectSound = AudioSounds.incorrect, incorrectSound.isPlaying {
			incorrectSound.pause()
			incorrectSound.currentTime = 0
		}
		
		if let correctSound = AudioSounds.correct, correctSound.isPlaying {
			correctSound.pause()
			correctSound.currentTime = 0
		}
	}
	
	// Alerts
	
	private func endOfQuestionsAlert() {
		
		let helpScore = oldScore - UserDefaultsManager.score
		let score = (correctAnswers * 20) - (incorrectAnswers * 10) - helpScore
		
		let title = "Score: ".localized + "\(score) pts"
		let message = "Correct answers: ".localized + "\(correctAnswers)" + "/" + "\(set.count)"
		
		let alertViewController = UIAlertController(title: title, message: message, preferredStyle: .alert)
		
		alertViewController.addAction(title: "OK".localized, style: .default) { action in self.okActionDetailed() }
		
		if (correctAnswers < set.count) && (repeatTimes < 2) && !isSetCompleted() {
			
			let repeatText = "Repeat".localized + " (\(2 - self.repeatTimes))"
			alertViewController.addAction(title: repeatText, style: .cancel) { action in self.repeatActionDetailed() }
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(75)) {
			self.present(alertViewController, animated: true)
		}
	}
	
	private func showOKAlertWith(title: String, message: String) {
		let alertViewController = UIAlertController.OKAlert(title: title, message: message)
		present(alertViewController, animated: true)
	}
	
	private func setUpQuiz() {
		self.set = SetOfTopics.shared.currentTopics[currentTopicIndex].quiz.topic[currentSetIndex].shuffled()
		self.quiz = set.enumerated().makeIterator()
	}
}
