(require :rtm-ros-robot-interface "package://hrpsys_ros_bridge/euslisp/rtm-ros-robot-interface.l")

(defclass datalogger-log-parser
  :super propertied-object
  :slots (file index count read-state time)
  )

(defmethod datalogger-log-parser
  (:init
   (fname &key (name))
   (send-super :name name)
   (setq file (open fname))
   (setq index 0 count 0)
   )
  (:reset
   (&key ((:count c) 0) ((:index i) 0))
   (let ((fname (send file :fname)))
     (close file)
     (setq file (open fname))
     (setq count c index i)
     ))
  (:fname () (send file :fname))
  (:read-state () read-state)
  (:time () time)
  (:proc
   ()
   (let (line)
     (when (< index count)
       (send self :reset :index index)
       )
     (while (>= index count)
       (unless (setq line (read-line file nil))
         (warn "hit EOF!~%")
         (send self :reset)
         (return-from :proc nil))
       (incf count)
       )
     (setq index count)

     (setq read-state (read-from-string (format nil "#f(~A)" (string-left-trim ".0123456789" line))))
     (let* ((tm (read-from-string (format nil "(~A)" (substitute (elt " " 0) (elt "." 0) (subseq line 0 (position (elt " " 0) line)))))))
       (setq time (instance ros::time :init :sec (car tm) :nsec (* 1000 (cadr tm)))))
     t
     ))
  )

(defun data-string-split ;; this function will be replaced by https://github.com/euslisp/EusLisp/issues/16
  (str separator)
  (let ((start-idx 0) (ret))
    (dotimes (i (length str))
      (when (= (elt str i) (elt separator 0))
        (push (subseq str start-idx i) ret)
        (setq start-idx (1+ i))))
    (if (/= start-idx (length str)) (push (subseq str start-idx) ret))
    (reverse ret)))

(defclass datalogger-log-parser-controller
  :super rtm-ros-robot-interface
  :slots (parser-list eof-p)
  )

(defmethod datalogger-log-parser-controller
  (:init
   (fname &key ((:robot r)))
   (setq robot (cond ((derivedp r metaclass) (instance r :init))
                     (t r)))
   ;;(send-super :init :robot r)
   (let* ((dir-str (format nil "/~A" (reduce #'(lambda (x y) (format nil "~A/~A" x y)) (cdr (pathname-directory fname)))))
          (fname-prefix (pathname-name fname)))
     ;; gather fname list with max lines
     (let* ((fname-candidate-list (remove-if-not #'(lambda (x) (substringp (format nil "~A." fname-prefix) x)) (directory dir-str)))
            (fname-liens-without-rh
             (mapcar #'(lambda (f)
                         (list (read-from-string (car (data-string-split (car (piped-fork-returns-list (format nil "LANG=C wc -l ~A/~A" dir-str f))) " "))) f))
                     (remove-if #'(lambda (x) (substringp "(" x)) fname-candidate-list)))
            (max-line (reduce #'(lambda (x y) (max x y)) (mapcar #'car fname-liens-without-rh)))
            (fname-candidate-list-with-valid-line-without-rh
             (mapcar #'cadr (remove-if-not #'(lambda (x) (= (car x) max-line)) fname-liens-without-rh))))
       (setq parser-list
             (mapcar #'(lambda (x)
                         (instance datalogger-log-parser :init (format nil "~A/~A" dir-str x)
                                   :name (let ((nm (pathname-type x)))
                                           (read-from-string
                                            (if (and (substringp "(" nm) (substringp ")" nm))
                                                (format nil "RobotHardware0_~A" (cadr (data-string-split nm "_")))
                                              nm)))))
                     (append (remove-if-not #'(lambda (x) (substringp "(" x)) fname-candidate-list)
                             fname-candidate-list-with-valid-line-without-rh)))
       )))
  (:parser-list
   (&optional (str))
   (if str
       (let ((str-sym (read-from-string str)))
         (find-if #'(lambda (x) (eq str-sym (send x :name))) parser-list))
     parser-list))
  (:eof-p () eof-p)
  (:update-robot-state
   (&key (wait-until-update nil))
   (setq eof-p (some #'null (send-all parser-list :proc)))
   (send self :set-robot-state1
         :reference-vector
         (map float-vector #'rad2deg (send (send self :parser-list "sh_qOut") :read-state)))
   (send self :set-robot-state1
         :potentio-vector
         (map float-vector #'rad2deg
              (send (send self :parser-list "RobotHardware0_q") :read-state)))
   (send robot :angle-vector (cdr (assoc :potentio-vector robot-state)))
   (send self :set-robot-state1
         :torque-vector
         (send (send self :parser-list "RobotHardware0_tau") :read-state))
   ;; (send robot :torque-vector (cdr (assoc :torque-vector robot-state)))
   (send self :set-robot-state1
         :reference-torque-vector
         (send (send self :parser-list "sh_tqOut") :read-state))
   (send self :set-robot-state1
         :reference-root-pos
         (scale 1e3 (send (send self :parser-list "sh_basePosOut") :read-state)))
   (send self :set-robot-state1
         :reference-root-rpy
         (send (send self :parser-list "sh_baseRpyOut") :read-state))
   (send self :set-robot-state1
         :reference-root-coords
         (make-coords :pos (cdr (assoc :reference-root-pos robot-state))
                      :rpy (cdr (assoc :reference-root-rpy robot-state))))
   (if (send self :parser-list "sh_zmpOut")
       (send self :set-robot-state1
             :zmp
             (send (send self :parser-list "sh_zmpOut") :read-state)))
   (dolist (f (send robot :force-sensors))
     (send self :set-robot-state1
           (send f :name)
           (send (send self :parser-list (format nil "RobotHardware0_~A" (send f :name))) :read-state))
     (send self :set-robot-state1
           (read-from-string (format nil ":off-~A" (string-downcase (send f :name))))
           (send (send self :parser-list (format nil "rmfo_off_~A" (send f :name))) :read-state)))
   ;; (dolist (i (send robot :imu-sensors))
   ;;   (send self :set-robot-state1
   ;;         (send i :name)
   ;;         (send (send self :parser-list (format nil "~A_~A" robothardware-name (send i :name))) :read-state)
   ;;         ))
   (when (send self :parser-list "kf_rpy")
     (send self :set-robot-state1
             :imu
             (let* ((rpy (send (send self :parser-list "kf_rpy") :read-state))
                    (qt (ros::rot->tf-quaternion (rpy-matrix (elt rpy 2) (elt rpy 1) (elt rpy 0)))))
               (instance* sensor_msgs::Imu :init
                          :orientation qt
                          (append
                           (if (send robot :imu-sensor "gsensor")
                               (list :linear_acceleration
                                     (let ((acc (send (send self :parser-list "RobotHardware0_gsensor") :read-state)))
                                       (instance geometry_msgs::Vector3 :init :x (elt acc 0) :y (elt acc 1) :z (elt acc 2)))))
                           (if (send robot :imu-sensor "gyrometer")
                               (list :angular_velocity
                                     (let ((gyro (send (send self :parser-list "RobotHardware0_gyrometer") :read-state)))
                                       (instance geometry_msgs::Vector3 :init :x (elt gyro 0) :y (elt gyro 1) :z (elt gyro 2))))))
                          )))
     (send robot :move-coords
           (make-coords :rot (ros::tf-quaternion->rot (send (cdr (assoc :imu robot-state)) :orientation)))
           (car (send robot :imu-sensors))))
   (if (send self :parser-list "abc_q")
       (send self :set-robot-state1
             :auto-balancer-reference-vector
             (map float-vector #'rad2deg (send (send self :parser-list "abc_q") :read-state))))
   (if (send self :parser-list "abc_baseTformOut")
       (send self :set-robot-state1
             :auto-balancer-reference-root-coords
             (send self :hrpsys-tform->coords (send (send self :parser-list "abc_baseTformOut") :read-state))))
   )
  (:hrpsys-tform->coords
   (tform-vector)
   (make-coords :pos (scale 1e3 (subseq tform-vector 0 3))
                :rot (make-matrix 3 3 (list (subseq tform-vector 3 6) (subseq tform-vector 6 9) (subseq tform-vector 9))))
   )
  (:reference-root-coords
   ()
   (cdr (assoc :reference-root-coords robot-state))
   )
  (:reference-worldcoords
   ()
   (send (send (send self :reference-root-coords) :copy-worldcoords)
         :transform
         (send (car (send robot :links)) :transformation robot))
   )
  (:auto-balancer-reference-vector () (cdr (assoc :auto-balancer-reference-vector robot-state)))
  (:auto-balancer-reference-root-coords () (cdr (assoc :auto-balancer-reference-root-coords robot-state)))
  ;; overwrite
  (:reference-vector () (cdr (assoc :reference-vector robot-state)))
  (:actual-vector () (send self :potentio-vector))
  (:error-vector () (v- (send self :potentio-vector) (send self :reference-vector)))
  (:time
   (&optional (str "sh_qOut"))
   (send (send self :parser-list str) :time)
   )
  )

;; (progn (setq *log* (instance datalogger-log-parser-controller :init "/tmp/testlog.sh_qOut")) (send *log* :state) (send *log* :potentio-vector))
