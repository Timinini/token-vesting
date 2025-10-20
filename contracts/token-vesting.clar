;; ------------------------------------------------------------
;; Time-Locked Token Release / Vesting Contract
;; Description:
;;  - Locks STX or FT tokens for beneficiaries.
;;  - Tokens are released automatically after a set block height.
;;  - Supports multiple beneficiaries and multiple locks.
;; ------------------------------------------------------------

;; Error constants
(define-constant ERR_NOT_ADMIN          (err u100))
(define-constant ERR_INVALID_AMOUNT     (err u101))
(define-constant ERR_ALREADY_EXISTS     (err u102))
(define-constant ERR_NO_LOCK_FOUND      (err u103))
(define-constant ERR_NOT_CLAIMABLE_YET  (err u104))
(define-constant ERR_TRANSFER_FAILED    (err u105))
(define-constant ERR_UNAUTHORIZED       (err u106))

;; Define trait for fungible tokens
(define-trait ft-trait
  ((transfer (uint principal principal) (response bool uint))))

;; Data variables
(define-data-var admin principal tx-sender)
(define-data-var lock-counter uint u0)

;; Map definitions
(define-map timelocks
  uint
  {
    beneficiary: principal,
    token-contract: (optional principal),
    amount: uint,
    unlock-block: uint,
    claimed: bool
  })

;; Create timelock for fungible tokens
(define-public (create-timelock 
  (beneficiary principal)
  (amount uint)
  (unlock-block uint)
  (token-principal principal))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= unlock-block burn-block-height) ERR_INVALID_AMOUNT)
    (asserts! (is-eq tx-sender (var-get admin)) ERR_NOT_ADMIN)
  (var-set lock-counter (+ (var-get lock-counter) u1))
  ;; Note: caller must ensure tokens are transferred to this contract before creating a timelock.
    (let ((new-id (var-get lock-counter)))
      (map-set timelocks new-id
        {
          beneficiary: beneficiary,
          token-contract: (some token-principal),
          amount: amount,
          unlock-block: unlock-block,
          claimed: false
        })
      (ok {
        lock-id: new-id,
        asset: "FT",
        amount: amount,
        unlock: unlock-block
      }))))

;; Create timelock for STX
(define-public (create-stx-timelock 
    (beneficiary principal)
    (amount uint)
    (unlock-block uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= unlock-block burn-block-height) ERR_INVALID_AMOUNT)
    (asserts! (is-eq tx-sender (var-get admin)) ERR_NOT_ADMIN)
    (var-set lock-counter (+ (var-get lock-counter) u1))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((new-id (var-get lock-counter)))
      (map-set timelocks new-id
        {
          beneficiary: beneficiary,
          token-contract: none,
          amount: amount,
          unlock-block: unlock-block,
          claimed: false
        })
      (ok {
        lock-id: new-id,
        asset: "STX",
        amount: amount,
        unlock: unlock-block
      }))))

;; Read-only functions
(define-read-only (get-lock (id uint))
  (ok (map-get? timelocks id)))

(define-read-only (get-total-locks)
  (ok (var-get lock-counter)))

;; Check if a timelock is claimable
(define-read-only (is-claimable (id uint))
  (let ((timelock-data (map-get? timelocks id)))
    (ok (match timelock-data
          timelock (and 
            (not (get claimed timelock))
            (>= burn-block-height (get unlock-block timelock)))
          false))))

;; Claim functions
;; claim-token: claims FT by lock-id using provided token trait
(define-private (claim-token (lock-id uint) (token <ft-trait>))
  (let ((timelock (unwrap-panic (map-get? timelocks lock-id))))
    (begin
      (try! (as-contract (contract-call? token transfer
        (get amount timelock)
        tx-sender
        (get beneficiary timelock))))
      (map-set timelocks lock-id (merge timelock {claimed: true}))
      (ok { claimed-by: (get beneficiary timelock), asset: "FT", amount: (get amount timelock) }))))

;; claim-stx: claims STX by lock-id
(define-private (claim-stx (lock-id uint))
  (let ((timelock (unwrap-panic (map-get? timelocks lock-id))))
    (begin
      (try! (as-contract (stx-transfer? (get amount timelock) tx-sender (get beneficiary timelock))))
      (map-set timelocks lock-id (merge timelock {claimed: true}))
      (ok { claimed-by: (get beneficiary timelock), asset: "STX", amount: (get amount timelock) }))))

;; Public claim function (STX only; FT use claim-ft)
(define-public (claim (lock-id uint))
  (match (map-get? timelocks lock-id)
    some-tl
      (begin
        (asserts! (is-eq tx-sender (get beneficiary some-tl)) ERR_UNAUTHORIZED)
        (asserts! (not (get claimed some-tl)) ERR_ALREADY_EXISTS)
        (asserts! (>= burn-block-height (get unlock-block some-tl)) ERR_NOT_CLAIMABLE_YET)
        (if (is-some (get token-contract some-tl))
            ERR_TRANSFER_FAILED
            (claim-stx lock-id)))
  ERR_NO_LOCK_FOUND))


;; Public claim function for fungible tokens (caller provides token trait instance)
(define-public (claim-ft (lock-id uint) (token <ft-trait>))
  (match (map-get? timelocks lock-id)
    some-tl
      (begin
        (asserts! (is-eq tx-sender (get beneficiary some-tl)) ERR_UNAUTHORIZED)
        (asserts! (not (get claimed some-tl)) ERR_ALREADY_EXISTS)
        (asserts! (>= burn-block-height (get unlock-block some-tl)) ERR_NOT_CLAIMABLE_YET)
        (match (get token-contract some-tl)
          stored-princ
            (begin
              (asserts! (is-eq stored-princ (contract-of token)) ERR_TRANSFER_FAILED)
              (claim-token lock-id token))
          ERR_NO_LOCK_FOUND))
  ERR_NO_LOCK_FOUND))
