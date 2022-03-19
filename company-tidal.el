;; -*- lexical-binding: t -*-
(require 'cl-lib)
(require 'comint)
(require 'company)

(defcustom company-tidal-candidates-limit 100
  ":complete repl に送る候補の数")


(defvar company-tidal--initialized nil
  "初期化されたかどうか")


(defvar company-tidal--output nil
  "output from tidal-buffer")


(defvar company-tidal--processing nil
  "ghciが処理中かどうか")


(defvar company-tidal--request-completion nil
  "request completion")


(defun company-tidal--create-request (req completion)
  "tidal (comint) にリクエストを送る"
  (setq company-tidal--processing t)
  (setq company-tidal--request-completion completion)
  (tidal-send-string req))


(defun company-tidal--find-candidates (string callback)
  "補完のリクエスト"
  (company-tidal--create-request
   (concat ":complete repl " (format "%d" company-tidal-candidates-limit) " \"" string "\"" "\n")
   (lambda (output)
     (let* ((outputs (split-string output "\n"))
            (outputs-without-prompt (seq-remove (lambda (item) (string-match "tidal>" item)) outputs))
            (outputs-without-quotes (seq-map (lambda (item) (string-trim item "\"" "\"")) outputs-without-prompt))
            (outputs-without-duplicate (delq nil (delete-dups outputs-without-quotes)))
            (result (seq-drop outputs-without-duplicate 1)))
       (funcall callback result)))))


(defun company-tidal--find-annotation (string callback)
  "annotation リクエスト"
  (company-tidal--create-request
   (concat ":type (" string ")\n")
   (lambda (output)
      (let* ((outputs (split-string output "\n"))
       (outputs-without-prompt (seq-remove (lambda (item) (string-match "tidal>" item)) outputs))
       (outputs-without-nil (delq nil outputs-without-prompt))
       (type-info (apply #'concatenate 'string outputs-without-nil))
       ;; :: で分けて関数名を削除
       (type-info-split-name (split-string type-info "::"))
       (type-info-without-name (seq-drop type-info-split-name 1))
       (result (apply #'concatenate 'string type-info-without-name)))
        (funcall callback (concat "::" result))))))


(defun company-tidal--preoutput-filter (output)
  "comint の出力フィルタ"
  (cond
   ;; 補完のリクエストがある場合は出力をしない
   (company-tidal--request-completion
    (let* ((match-prompt (string-match "tidal>" output)))
      ;; output を company-tidal--output に結合
      (setq company-tidal--output (concat company-tidal--output output))
      ;; "output に tidal> プロンプトがある場合、company-tidal--request-completion に出力"
      (when (and match-prompt)
        (let* ((output company-tidal--output)
               (request-completion company-tidal--request-completion))
          (funcall request-completion output)
          (setq company-tidal--output nil)
          (setq company-tidal--request-completion nil)
          )))
    "")
   ;; 処理中の場合は出力をしない
   (company-tidal--processing "")
   ;; 通常の出力
   (t output)))


(defun company-tidal--finish ()
  "終了処理"
  (setq company-tidal--processing nil))


(defun company-tidal--post-completion (string)
  "完了処理"
  (company-tidal--finish))


(defun company-tidal--completion-cancelled (arg)
  "キャンセル処理"
  (company-tidal--finish))


(defun company-tidal (command &optional arg &rest ignored)
  "Company backend for TidalCycles"
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-tidal))
    ;; 初期化処理
    ;; 'tidal-send-string が存在しない場合は起動しない
    (init (if (fboundp 'tidal-send-string)
              (unless company-tidal--initialized
                (add-hook 'company-completion-cancelled-hook 'company-tidal--completion-cancelled)
                (with-current-buffer tidal-buffer
                  (add-hook 'comint-preoutput-filter-functions 'company-tidal--preoutput-filter))
                (setq company-tidal--initialized t))
            (error "no tidal process running?")))
    (prefix (and (eq major-mode 'tidal-mode)
                 (company-grab-symbol)))
    (candidates (cons :async
                      (lambda (callback)
                        (company-tidal--find-candidates arg callback))))
    (annotation (cons :async
                      (lambda (callback)
                        (company-tidal--find-annotation arg callback))))
    (post-completion (company-tidal--post-completion arg))
  ))


(provide 'company-tidal)

