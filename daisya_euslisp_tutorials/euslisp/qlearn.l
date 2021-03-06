;;**************************************************
;;
;;  Q-Learning
;;
;;           Takashi Ogura
;;                               2005/1/17
;;
;;**************************************************

(defclass mdp-qagent
  :super propertied-object
  :slots (q actions environment time
	    policy             ; e-greedy is default
	    alpha gamma epsilon  ; learning params
	    )
  )

(defmethod mdp-qagent
  (:init (act env &key ((:alpha a) 0.1) ((:gamma g) 0.95) ((:epsilon e) 0.1))
    (setq actions act
	  environment env)
    (setq alpha a
	  gamma g
	  epsilon e)
    (setq time 0)
    (setq policy :e-greedy)
    ;;
    (setq q nil)
    (dotimes (i (length actions))
      (push (make-array (send env :state-size) :initial-element 0) q))
    self)
  (:time (&optional tm)(if tm (setq time tm) time))
  (:q (s a &optional new-value)
    (if new-value
	(setf (elt (elt q a) s) new-value))
    (elt (elt q a) s)
    )
  (:max-q (s)
    (let ((max-q -100000) ai)
      (dotimes (i (length actions))
	(when (> (send self :q s i) max-q)
	  (setq max-q (send self :q s i))
	  (setq ai (list i)))
	(when (= (send self :q s i) max-q)
	  (push i ai)
	  ))
      (cons max-q ai)))
  ;;
  (:act (state)
    (send self policy state))
  ;; policy types
  (:random (state)
    (random (length actions)))
  (:e-greedy (state)
    (let (ret)
      (cond
       ((= (random (round (/ 1.0 epsilon))) 0)
	(random (length actions)))
       (t
	(setq ret (cdr (send self :max-q state)))
	(setq ret (elt ret (random (length ret))))))))
  (:greedy (state)
    (let (ret)
      (setq ret (cdr (send self :max-q state)))
      (setq ret (elt ret (random (length ret))))))
  (:boltzmann (state)
    ) ;; not implemented yet
  ;;
  (:state ()
    (send environment :state))
  (:policy-proc ()
    (let (st at)
      (setq st (send self :state))     ; get state
      (setq at (send self :greedy st))    ; select action
      (send self (elt actions at))     ; do action
      ))
  (:proc ()
    (let (st at r st+1)
      (setq st (send self :state))     ; get state
      (setq at (send self :act st))    ; select action
      (send self (elt actions at))     ; do action
      (setq r (send environment :r))   ; get reward
      (setq st+1 (send self :state))   ; get next state
      (incf time)
      (send self :q st at
	    (+ (* (- 1 alpha) (send self :q st at))
	       (* alpha (+ r (* gamma (car (send self :max-q st+1)))))))
      ))
  )

;; Sutton (1990)
(defclass mdp-dyna-qagent
  :super mdp-qagent
  :slots (num model ex-states ex-state-actions)
  )

(defmethod mdp-dyna-qagent
  (:init (an &rest args)
    (setq num an)
    (send-super* :init args))
  (:update-model (st at st+1 r)
    ;; $B:G?7$N>pJs$rF~$l$k(B
    (let ((old-exp (assoc (list st at) model :test #'equal)))
      (when (and old-exp
		 (not (equal old-exp (cons (list st at) (list st+1 r)))))
	(format t ";; model changed!~%")
	(setq model (remove old-exp model :test #'equal)))
      (push (cons (list st at) (list st+1 r)) model)
      ;;(pushnew (cons (list st at) (list st+1 r)) model :test #'equal)
      ))
  (:simulate (st at)
    (cdr (assoc (list st at) model :test #'equal))
    )
  (:add-experiment (st at)
    (let (state-action)
      (pushnew st ex-states)
      (cond
       ((setq state-action (assoc st ex-state-actions))
	(nconc state-action (list at)))
       (t
	(push (list st at) ex-state-actions)))))
  (:proc ()
    (let (st at r st+1 st-r ex-actions)
      (setq st (send self :state))     ; get state
      (setq at (send self :act st))    ; select action
      (send self (elt actions at))     ; do action
      (setq r (send environment :r))   ; get reward
      (setq st+1 (send self :state))   ; get next state
      (incf time)
      ;; $BD>@\E*6/2=3X=,(B
      (send self :q st at
	    (+ (* (- 1 alpha) (send self :q st at))
	       (* alpha (+ r (* gamma (car (send self :max-q st+1)))))))
      ;; $B%b%G%k3X=,(B
      (send self :update-model st at st+1 r)
      ;; $B%W%i%s%K%s%0(B
      (send self :add-experiment st at)
      (dotimes (i num)
	(setq st (elt ex-states (random (length ex-states))))
	(setq ex-actions (cdr (assoc st ex-state-actions)))
	(setq at (elt ex-actions (random (length ex-actions))))
	(setq st-r (send self :simulate st at))
	(setq st+1 (car st-r) r (cadr st-r))
	(send self :q st at
	      (+ (* (- 1 alpha) (send self :q st at))
		 (* alpha (+ r (* gamma (car (send self :max-q st+1))))))))
      ))
  )

;; Moore and Atkeson (1993) and Peng and Williams (1993)
(defclass mdp-prioritized-sweeping-agent
  :super mdp-dyna-qagent
  :slots (pqueue)
  )
(defmethod mdp-prioritized-sweeping-agent
  (:init (&rest args)
    (setq pqueue (instance queue :init))
    (send-super* :init args))
  ;; state s$B$K$D$J$,$k(Bs_, a_$B$r5a$a$k(B
  (:simulate-back (s)
    (let (s-a)
      (dolist (m model)
	(if (equal (car (cdr m)) s)
	    (push (car m) s-a)))
      s-a))
  (:proc ()
    (let (st at r p (theta 0) st+1 s-a st-r ex-actions st_ at_ r_)
      (setq st (send self :state))     ; get state
      (setq at (send self :act st))    ; select action
      (send self (elt actions at))     ; do action
      (setq r (send environment :r))   ; get reward
      (setq st+1 (send self :state))   ; get next state
      ;; $B%b%G%k3X=,(B
      (send self :update-model st at st+1 r)
      (incf time)
      (setq p (- (+ r (* gamma (car (send self :max-q st+1))))
		 (send self :q st at)))
      (if (> p theta)
	  (send pqueue :enqueue-by-priority (list (cons st at)) #'(lambda(x) p)))
      (dotimes (i num)
	(if (send q :emptyp) (return))
	(setq s-a (send pqueue :remove-front))
	(setq st (car s-a) at (cdr s-a))
	(setq st-r (send self :simulate st at))
	(setq st+1 (car st-r) r (cadr st-r))
	(send self :q st at
	      (+ (* (- 1 alpha) (send self :q st at))
		 (* alpha (+ r (* gamma (car (send self :max-q st+1)))))))
	;;
	(dolist (s_-a_ (send self :simulate-back st))
	  (setq st_ (car s_-a_) at_ (cdr s_-a_))
	  (setq st-r (send self :simulate st_ at_))
	  (setq r_ (cadr st-r))
	  (setq p (- (+ r_ (* gamma (car (send self :max-q st+1))))
		     (send self :q st_ at_)))
	  (if (> p theta)
	      (send pqueue :enqueue-by-priority (list (cons st_ at_)) #'(lambda(x) p)))
	  )
	)
      ))
  )

;; Bradtke and Duff (1995)
(defclass smdp-qagent
  :super mdp-qagent
  :slots (dead-lock-num)
  )

(defmethod smdp-qagent
  (:init (&rest args)
    (setq dead-lock-num 3)
    (send-super* :init args))
  (:proc ()
    (let (event st at (r 0) (count 0) st+n)
      (setq st (send self :state))
      (setq at (send self :act st))
      (setq st+n st)
      (while (equal st st+n) ;; $B>uBVJQ2=(B
	(send self (elt actions at))
	(incf r (* (expt gamma count) (send environment :r)))
	(incf count)
	(setq st+n (send self :state))
	;;(when (not (equal st st+n)) ;; $B>uBVJQ2=(B
	;;(setq event t))
	(when (> count dead-lock-num)  ;; dead lock ?
	  (setq at (send self :random st))
	  (setq count 0 r 0)
	  )
	)
      (incf time count) ;; dead lock$B$OL5$+$C$?$3$H$K$9$k(B
      (send self :q st at
	    (+ (* (- 1 alpha) (send self :q st at))
	       (* alpha (+ r (* (expt gamma count) (car (send self :max-q st+n)))))))
      ))
  )


(defclass mdp-search-agent
  :super mdp-qagent
  :slots nil)
(defmethod mdp-search-agent
  (:init (env)
    (send-super :init '(:u :d :r :l) env)
    )
  (:u ()
    (send environment :u-go))
  (:d ()
    (send environment :d-go))
  (:r ()
    (send environment :r-go))
  (:l ()
    (send environment :l-go))
  )


(defclass mdp-dyna-search-agent
  :super mdp-dyna-qagent
  :slots nil)
(defmethod mdp-dyna-search-agent
  (:init (env &optional (num 3))
    (send-super :init num '(:u :d :r :l) env)
    )
  (:u ()
    (send environment :u-go))
  (:d ()
    (send environment :d-go))
  (:r ()
    (send environment :r-go))
  (:l ()
    (send environment :l-go))
  )

(defclass smdp-search-agent
  :super smdp-qagent
  :slots nil)
(defmethod smdp-search-agent
  (:init (env)
    (send-super :init '(:u :d :r :l) env)
    )
  (:u ()
    (send environment :u-go))
  (:d ()
    (send environment :d-go))
  (:r ()
    (send environment :r-go))
  (:l ()
    (send environment :l-go))
  )

;;$B4D6-%/%i%9(B
(defclass mdp-qenvironment
  :super propertied-object
  :slots (state reward)
  )
(defmethod mdp-qenvironment
  (:init ()
    (setq reward 0)
    self)
  (:state (&optional st)
    (if st (setq state st) state))
  (:r () reward)
  )


;;;
;;;$B62$i$/CO?^4D6-$N:n@.$r$7$F$$$k(B
;;;
(defclass mdp-search-environment
  :super mdp-qenvironment
  :slots (width height sp rp ob xy step ngoal))
(defmethod mdp-search-environment
  (:init (map &key ((:step stp) 1))
    (send-super :init)
    (setq step stp)
    ;;
    (send self :read-map map) ;;rp,sp,ob$B$N:BI8$N@_Dj(B
    (send self :initialize)
    self)
  (:state-size () (* width height))
  ;;map$B$O(Bx,-,x,g$B$GI=$5$l$?0J2<$N$h$&$JJ8;zNs$N(Blist$B$rA[Dj$7$F$$$k(B
  #|
	       "xxxxxxxxxxx"
	       "x-------xgx"
	       "x--x----x-x"
	       "xs-x----x-x"
	       "x--x------x"
	       "x-----x---x"
	       "x---------x"
	       "xxxxxxxxxxx"
  |#
  ;;$B$3$l$r2r<a$7$F!"CO?^4D6-!J(Bstate)$B$rF~$l$F$$$k$_$?$$(B
  (:read-map (map)
    ;;$BCO?^$N=D2#$r3JG<(B
    (setq width (length (car map)))
    (setq height (length map))
    (setq ob nil)
    (dotimes (i height)
      (dotimes (j width)
	(cond
	 ;;g$B$N:BI8$K$O(Brp = reward point?$B$r@_Dj(B
	 ((= (elt (elt map i) j) #\g)
	  (setq rp (float-vector j i)))
	 ;;s$B$N:BI8$K$O(Bsp = start point? $B$r@_Dj(B
	 ((= (elt (elt map i) j) #\s)
	  (setq sp (float-vector j i)))
	 ;;x$B$N:BI8$K$O!"(Bob = obstacle$B$N(Blist $B$r@_Dj(B
	 ((= (elt (elt map i) j) #\x)
	  (push (float-vector j i) ob))
	 )
	))
    )
  ;;state$B$r3JG<(B state$B$O?tCM$N$h$&$@(B
  (:initialize ()
    (setq ngoal 0)  ;;goal$B$K$D$$$?2s?t$r(Breset
    (setq xy (copy-object sp)) ;;$B8=:_CM$r%9%?!<%HCOE@$K(B
    (setq state (send self :xy2state xy)) ;;$B8=:_(Bstate$B$r8=:_:BI8$+$i7W;;(B
    )
  ;;$B:BI8$r(Bstate$B!J?tCM!K$KJQ49(B
  (:xy2state (axy) (+ (* width (floor (elt axy 1))) (floor (elt axy 0))))
  ;;state$B$r:BI8$KLa$9(B
  (:state2xy (astate) (float-vector (mod astate width) (floor (/ astate width))))
  ;;$B8=:_$N(Bstate$B$rJV$9!"$"$k$$$O@_Dj$5$l$?(Bstate$B$r8=:_(Bstate$B$K%;%C%H$9$k!#Nc30=hM}$D$-(B
  (:state (&optional st)
    (if (and st
	     (>= st 0)
	     (< st (* width height)))
	(setq state st))
    state)
  ;;goal$B$KE~C#$7$?$+$r3NG'$9$k(B
  (:goalp (&optional (st state))
    (equal (send self :state2xy st) rp))
  ;;$B>c32J*$+$r3NG'$9$k(B
  (:obstaclep (&optional (st state))
    (member (send self :state2xy st) ob :test #'equal))
  ;;$BCO?^>pJs$rI=<($9$k(B
  (:print ()
    (dotimes (i height)
      (dotimes (j width)
	(cond
	 ;;$B8=:_0LCV$rI=<($9$k$N$O(B#
	 ((= (send self :xy2state (float-vector j i)) state)
	  (format t "#"))
	 ((send self :goalp (send self :xy2state (float-vector j i)))
	  (format t "g"))
	 ((send self :obstaclep (send self :xy2state (float-vector j i)))
	  (format t "x"))
	 (t
	  (format t "-"))))
      (format t "~%"))
    )
  ;;$BCO?^$NCf$K$$$k$+$I$&$+(B
  (:insidep (&optional (st state))
    (and (>= st 0) (< st (* width height))))
  ;;$B8=:_$h$j$bAjBPE*$K:BI8J}8~$X$$$/(B
  ;; xy$B$O8=:_$N:BI8$,F~$k(B
  (:go (dxy)
    (let (i sign nxy nstate)
      ;;x,y$B$I$C$AJ}8~$K?J$`$+$N(Bi$B$rD4$Y$k(B
      ;; $B$o$+$j$K$/$$$1$I!"(Bx$B$K?J$`$J$i(Bi$B$O#0!"(By$B$K?J$J$i(Bi$B$O#1$K$J$k!#(B
      (setq i (floor (abs (elt dxy 1))))
      ;; $B$I$C$AJ}8~$K?J$`$+$r7h$a$F$$$k(B
      (setq sign (if (> (elt dxy i) 0) 1 -1))
      (setq nxy (copy-object xy))
      ;;step$B$V$s$@$1?J$`:BI8$r:n$k(B
      (incf (elt nxy i) (* sign step))
      ;;$B$9$9$s$@>l9g$N(Bstate$B$r<hF@$9$k(B
      (setq nstate (send self :xy2state nxy))
      ;; calc reward
      ;;  nstate$B$,(Bgoal$B$@$C$?$i(B1$B$r!"(Bobstacle$B$J$i(B0$B$rJV$9!"$=$l0J30$b#0$r(B
      ;;  goal$B$@$H$O$8$a$FJs=7(B
      (setq reward
	    (cond
	     ((send self :goalp nstate) 1) ;; goal
	     ((send self :obstaclep nstate) 0) ;; obstacles
	     (t 0)))
      ;; $BF0$/$+$I$&$+$rH=Dj$9$k(B
      (cond
       ;; don't move       
       ;;  $B$7$g$&$,$$$V$D$@$C$?$j30$K$$$C$F$?$iF0$+$J$$(B
       ((or (send self :obstaclep nstate)
	    (not (send self :insidep nstate)))
	)
       ;; goal$B$@$C$?$i(Bgoal$B$K$D$$$?2s?t(Bngoal$B$r99?7$9$k(B
       ;; $B$G!"%9%?!<%H$KLa$k(B
       ((send self :goalp nstate);; goal
	(incf ngoal)
	(setq xy (copy-object sp))) ;; return to start
       ;; $B$=$l0J30$O99?7$9$k(B
       (t
	(setq xy nxy)
	)
       )
      ;;
      ;;$B8=:_:BI8(Bxy$B$K(Bstate$B$r99?7$9$k(B
      (send self :state (send self :xy2state xy))))
  ;;$B$R$H$D>e$K$$$/(B
  (:u-go ()
    (send self :go (float-vector 0 1)))
  ;;$B$R$H$D2<$K$$$/(B
  (:d-go ()
    (send self :go (float-vector 0 -1)))
  ;;$B$R$H$D:8$K$$$/(B
  (:l-go ()
    (send self :go (float-vector -1 0)))
  ;;$B$R$H$D1&$K$$$/(B
  (:r-go ()
    (send self :go (float-vector 1 0)))
  )

;;agent$B$N@/:v$rD4$Y$k$i$7$$(B
;; $B$7$F$k$3$H$O!"(Bagent$B$N4D6-$N(Bgoal$BE~C#2s?t$7$?2s?t$@$1(B
;; agent$B$N(Bpolicy-proc$B$rFI$s$G$$$k(B
;; $B8=:_$N>uBV$G!"(Bgoal$B$9$k$^$G$KI,MW$J%9%F%C%W?t$rJV$9(B?
;;
(defun check-policy (a &optional (debug nil) (time 500))
  (let* ((env (a . environment))
	 (tgcount (env . ngoal))
	 (tcount 0))
    ;;$B$b$&0lEY%4!<%k$9$k$^$G(B send a :policy-proc$B$r9T$&(B
    (while (= tgcount (env . ngoal))
      (send a :policy-proc)
      (when debug
	(send env :print)
	(format t ";~%")
	(unix:usleep (* time 1000))
	)
      (incf tcount)
      )
    ;;tcount$B$O$b$&0lEY%4!<%k$9$k$^$G$KI,MW$J%9%F%C%W?t(B
    (setq (env . ngoal) tgcount)
    tcount))

;;
;;$B3X=,?k9T4X?t(B 
;; a$B$O(Bagent$B$N(Binstance$B$rF~$l$k$N$+$J(B
;; agent$B$N(B time, proc$B$,2?$r$7$F$$$k$N$+$rD4$Y$kI,MW$,$"$k(B
(defun learn (a &optional (fname "qlearn.dat") &key debug)
  (let ((max-time 10000) (max-goal 100) (rcount 0) (gcount 0) (max-repeat 20)
	v (env (a . environment))
	(tcount 0) ptcount)
    ;;agent$B$N4D6-$r=i4|2=$9$k(B($BCO?^$N%9%?!<%HCOE@$KLa$9!"%4!<%kE~C#2s?t$r(B0$B$KLa$9(B)
    (send env :initialize)
    ;;$B3X=,3+;O(B
    (with-open-file (f fname :direction :output)
      (loop
       (when (= rcount max-repeat)
	 ;;$B2?DL$j$K<}B+$7$?$+(B
	 ;; gcount$B$O%4!<%k$7$?2s?t(B
	 (format t ";~%converged in ~A goals !~%" (- gcount rcount))
	 (return))
       ;;$B<}B+$7$J$+$C$?>l9g(B
       (when (or (> gcount max-goal)
		 (> (send a :time) max-time))
	 (format t ";~%NOT converged!~%")
	 (return))
       ;;
       ;;$BB?J,$3$l$,4N(B($B$*$=$i$/#1%9%F%C%W?J$a$k!K(B
       (send a :proc)
       ;;
       ;;$BCO?^>pJs$rI=<((B
       (when debug
	 (send env :print)
	 (format t "~%"))
       ;;
       ;;$B0lEY(Bgoal$B$KE~C#$9$kEY$K9T$&=hM}(B
       ;; goal$B$KE~C#$9$k$H(Benv$B$N(Bngoal$B$,A}$($k$N$G!"(Blearn$B$GJ];}$7$F$$$k(Bgcount$B$H$:$l$k(B
       ;; $B$N$G$o$+$k(B
       (when (not (= (env . ngoal) gcount))
	 (setq gcount (copy-object (env . ngoal)))
	 ;;agent$B$N(Btime$B$rJV$9(B($B$*$=$i$/!"(Bgoal$B$^$G$KE~C#$9$k$N$K$+$+$C$?%9%F%C%W?t(B)
	 (format t ";~5d :" (setq v (send a :time)))
	 (dotimes (i (floor (/ (send a :time) 10))) ;;$B$+$+$C$?%9%F%C%W?t$r;k3PE*$KI=$7$?$@$1(B($B$J$s$@(Borz)
	   (format t ";*"))
	 (format t "~%")
	 ;;$B@/:v$rD4$Y$k(B  .. tcount$B$K$O(Bgoal$B$^$G$KI,MW$J(Bstep$B?t$,F~$k(B($BB?J,(B)
	 (setq tcount (check-policy a))
	 ;;
	 (format f "~A~%" v)
	 ;;
	 ;;agent$B$N2s?t$r(Breset
	 (send a :time 0)
	 ;;
	 ;;ptcount$B$OA02s$N(Btcount, tcount$B$O(B check-policy$B$NJV$jCM(B
	 ;; $BA02s$HF1$8$J$i!"(Brcount$B$r$U$d$9(B
	 ;; rcount$B$O2?2sO"B3$GF1$8(Btcount$B$,=P$?$+$rD4$Y$k0z?t$+(B
	 (if (equal tcount ptcount) (incf rcount) (setq rcount 0))
	 (setq ptcount tcount)
	 )))
    (format t "~%")
    ))

#|
;;$B7k6II,MW$J$N$O!"(Bmap$B$NMQ0U!"4D6-$NMQ0U!"(Bagent$B$NMQ0U(B
;; $B%7%s%\%k6u4V$GLBO)$r2r7h$9$k(Bsample
(defun hoge
  (&optional (debug nil))
  (setq map (list
	     "xxxxxxxxxxxxxxxx"
	     "x--------------x"
	     "x-s--x---------x"
	     "x------xxx-----x"
	     "x----x---------x"
	     "x-----xx--xxx--x"
	     "x-----x-x-x----x"
	     "x-----x--xx--g-x"
	     "x--------------x"
	     "xxxxxxxxxxxxxxxx"
	     ))
  ;;$B4D6-$N9=C[(B
  (setq se (instance mdp-search-environment :init map))
  ;;$B%(!<%8%'%s%H$N9=C[(B
  ;; ($B$$$/$D$+J}:v$,$"$k$1$I!"<}B+$^$G$K$+$+$k;~4V$,0c$&(B)
  ;;(setq nna (instance mdp-dyna-search-agent :init se))
  ;;(setq nna (instance mdp-search-agent :init se))
  (setq nna (instance smdp-search-agent :init se))
  ;;$B3X=,(B
  (learn nna "qlearn-map1.dat" :debug debug)
  ;;
  ;;$B2r$$$F$_$F$h!*(B
  (check-policy nna t 200)
  ;;
  )
|#
