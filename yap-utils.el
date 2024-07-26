;;; yap-utils.el --- Bunch of util functions for yap -*- lexical-binding: t; -*-

;;; Commentary:
;; Bunch of util functions for yap

;;; Code:
(defvar yap--response-buffer "*yap-response*")

(defun yap--parse-csv-line (line)
  "Parse a CSV LINE into a list of fields, handling quotes properly."
  (let ((result '())
        (field "")
        (in-quote nil)
        (i 0))
    (while (< i (length line))
      (let ((char (aref line i)))
        (cond
         ((and (not in-quote) (eq char ?,))
          ;; Comma outside quotes: end of field
          (push (string-trim field) result)
          (setq field ""))
         ((eq char ?\")
          ;; Quote character
          (if in-quote
              (if (and (< (1+ i) (length line)) (eq (aref line (1+ i)) ?\"))
                  ;; Escaped quote
                  (progn
                    (setq field (concat field "\""))
                    (cl-incf i))
                ;; End of quoted field
                (setq in-quote nil))
            ;; Start of quoted field
            (setq in-quote t)))
         (t
          ;; Any other character
          (setq field (concat field (char-to-string char)))))
        (cl-incf i)))
    ;; Add the last field
    (push (string-trim field) result)
    ;; Return the fields in correct order
    (nreverse result)))

(defun yap--get-error-message (object)
  "Parse out error message from the OBJECT if possible."
  (if (alist-get 'error object)
      (alist-get 'message (alist-get 'error object))
    object))

(defun yap--convert-messages (messages)
  "Convert MESSAGES from (role . content) to OpenAI format."
  (mapcar (lambda (pair)
            (let ((role (car pair))
                  (content (cdr pair)))
              `(("role" . ,role) ("content" . ,content))))
          messages))

(defun yap--convert-messages-sans-system (messages)
  "Convert MESSAGES from (role . content) to OpenAI format, without system message."
  (mapcar (lambda (pair)
            (let ((role (car pair))
                  (content (cdr pair)))
              (if (not (string= role "system"))
                  `(("role" . ,role) ("content" . ,content))
                nil)))
          messages))

(defun yap--system-message (messages)
  "Check if the given MESSAGES contain a system message."
  (let ((system-message (seq-find (lambda (pair)
                                    (string= (car pair) "system"))
                                  messages)))
    (if system-message
        (cdr system-message)
      nil)))

(defun yap--present-response (response)
  "Present the RESPONSE in a posframe or a new buffer, defaulting to the echo area.
You can always call `yap-display-output-buffer' to view the output in
a separate buffer."
  (let ((buffer (get-buffer-create yap--response-buffer)))
    (with-current-buffer buffer
      (erase-buffer)
      (insert response)
      ;; Enable markdown mode if available
      (if (fboundp 'markdown-mode) (markdown-mode)))
    (if (or yap-respond-in-buffer (> (length response) yap-respond-in-buffer-threshold))
        (display-buffer buffer)
      (if (and (featurep 'posframe) (fboundp 'posframe-show) (not yap-no-popup))
          (posframe-show " *yap-response*"
                         :string response
                         :timeout yap-popup-timeout
                         :border-width 2
                         :min-width 36
                         :max-width fill-column
                         :min-height 1
                         :left-fringe 8
                         :right-fringe 8
                         :border-color (face-attribute 'vertical-border :foreground)
                         :position (point))
        (message response)))))

(defun yap-display-output-buffer ()
  "Display the output buffer for yap."
  (interactive)
  (display-buffer yap--response-buffer))

(defun yap--show-diff (before after)
  "Show the diff between BEFORE and AFTER."
  ;; TODO: Use diff package
  (let ((diff (substring-no-properties
               (shell-command-to-string
                (format "diff -u <(echo %s) <(echo %s)"
                        (shell-quote-argument before)
                        (shell-quote-argument after))))))
    (format "%s" diff)))

(defun yap--rewrite-buffer-or-selection (response buffer)
  "Replace the buffer or selection with the given RESPONSE in BUFFER."
  (with-current-buffer buffer
    (if response
        (let* ((to-replace (if (region-active-p)
                               (buffer-substring-no-properties (region-beginning) (region-end))
                             (buffer-string)))
               (diff (yap--show-diff to-replace response)))
          (if (or (not yap-show-diff-before-rewrite)
                  (yes-or-no-p (format "%s\nDo you want to apply the following changes? " diff)))
              (if (region-active-p)
                  (progn
                    (delete-region (region-beginning) (region-end))
                    (insert response "\n"))
                (progn
                  (delete-region (point-min) (point-max))
                  (insert response)))
            (message "No changes made.")))
      (message "[ERROR] Failed to get a response from LLM"))))

(provide 'yap-utils)
;;; yap-utils.el ends here