;; gameweave-registry
;; 
;; This contract serves as the central hub for the GameWeave platform, enabling interoperability
;; of NFT assets across different games on the Stacks blockchain. It allows game developers to:
;; 1. Register their games in the GameWeave ecosystem
;; 2. Define mappings for how their NFT assets translate to other games
;; 3. Specify compatibility rules for cross-game NFT usage
;;
;; The contract maintains a registry of games, their supported NFT collections, and the
;; translation rules between different games' asset structures, serving as the backbone
;; for a seamless cross-game NFT experience.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-GAME-EXISTS (err u101))
(define-constant ERR-GAME-NOT-FOUND (err u102))
(define-constant ERR-COLLECTION-EXISTS (err u103))
(define-constant ERR-COLLECTION-NOT-FOUND (err u104))
(define-constant ERR-MAPPING-EXISTS (err u105))
(define-constant ERR-MAPPING-NOT-FOUND (err u106))
(define-constant ERR-INVALID-PARAMETERS (err u107))

;; Data structures

;; Admin of the GameWeave registry
(define-data-var contract-owner principal tx-sender)

;; Game registration data
(define-map games
  { game-id: (string-ascii 64) }
  {
    owner: principal,
    name: (string-utf8 100),
    description: (string-utf8 500),
    metadata-uri: (optional (string-utf8 256)),
    active: bool
  }
)

;; NFT collections supported by each game
(define-map game-collections
  { 
    game-id: (string-ascii 64),
    collection-contract: principal
  }
  {
    name: (string-utf8 100),
    description: (string-utf8 500),
    attributes: (list 20 (string-ascii 64)), ;; List of supported attributes
    active: bool
  }
)

;; NFT asset mapping between games
(define-map asset-mappings
  {
    source-game-id: (string-ascii 64),
    source-collection: principal,
    target-game-id: (string-ascii 64)
  }
  {
    target-collection: principal,
    attribute-mappings: (list 20 {
      source-attribute: (string-ascii 64),
      target-attribute: (string-ascii 64),
      transformation: (optional (string-ascii 64)) ;; Optional transformation rule
    }),
    active: bool
  }
)

;; Private functions

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is game owner
(define-private (is-game-owner (game-id (string-ascii 64)))
  (match (map-get? games { game-id: game-id })
    game-data (is-eq tx-sender (get owner game-data))
    false
  )
)

;; Check if a game exists
(define-private (game-exists (game-id (string-ascii 64)))
  (is-some (map-get? games { game-id: game-id }))
)

;; Read-only functions

;; Get game information
(define-read-only (get-game (game-id (string-ascii 64)))
  (map-get? games { game-id: game-id })
)

;; Get collection information for a specific game
(define-read-only (get-game-collection 
  (game-id (string-ascii 64)) 
  (collection-contract principal)
)
  (map-get? game-collections { 
    game-id: game-id, 
    collection-contract: collection-contract 
  })
)

;; Get all collections for a game
(define-read-only (get-game-collections (game-id (string-ascii 64)))
  (map-get? game-collections { game-id: game-id, collection-contract: contract-caller })
)

;; Get asset mapping between games
(define-read-only (get-asset-mapping 
  (source-game-id (string-ascii 64))
  (source-collection principal)
  (target-game-id (string-ascii 64))
)
  (map-get? asset-mappings {
    source-game-id: source-game-id,
    source-collection: source-collection,
    target-game-id: target-game-id
  })
)

;; Check if an NFT is compatible with a target game
(define-read-only (is-nft-compatible 
  (source-game-id (string-ascii 64))
  (source-collection principal)
  (target-game-id (string-ascii 64))
)
  (match (map-get? asset-mappings {
    source-game-id: source-game-id,
    source-collection: source-collection,
    target-game-id: target-game-id
  })
    mapping (get active mapping)
    false
  )
)

;; Public functions

;; Set a new contract owner
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

;; Register a new game
(define-public (register-game 
  (game-id (string-ascii 64))
  (name (string-utf8 100))
  (description (string-utf8 500))
  (metadata-uri (optional (string-utf8 256)))
)
  (begin
    (asserts! (not (game-exists game-id)) ERR-GAME-EXISTS)
    (map-set games
      { game-id: game-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        metadata-uri: metadata-uri,
        active: true
      }
    )
    (ok true)
  )
)

;; Update game information
(define-public (update-game 
  (game-id (string-ascii 64))
  (name (string-utf8 100))
  (description (string-utf8 500))
  (metadata-uri (optional (string-utf8 256)))
  (active bool)
)
  (begin
    (asserts! (game-exists game-id) ERR-GAME-NOT-FOUND)
    (asserts! (is-game-owner game-id) ERR-NOT-AUTHORIZED)
    
    (map-set games
      { game-id: game-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        metadata-uri: metadata-uri,
        active: active
      }
    )
    (ok true)
  )
)

;; Transfer game ownership
(define-public (transfer-game-ownership 
  (game-id (string-ascii 64))
  (new-owner principal)
)
  (begin
    (asserts! (game-exists game-id) ERR-GAME-NOT-FOUND)
    (asserts! (is-game-owner game-id) ERR-NOT-AUTHORIZED)

    ;; Get game data (asserts guarantee it exists, use unwrap-panic)
    (let ((game-data (unwrap-panic (map-get? games { game-id: game-id }))))
      ;; Update map (map-set returns true, but we ignore it here)
      (map-set games { game-id: game-id } (merge game-data { owner: new-owner }))
    ) ;; End of let scope

    ;; Return success for the public function
    (ok true)
  )
)

;; Register a collection for a game
(define-public (register-collection
  (game-id (string-ascii 64))
  (collection-contract principal)
  (name (string-utf8 100))
  (description (string-utf8 500))
  (attributes (list 20 (string-ascii 64)))
)
  (begin
    (asserts! (game-exists game-id) ERR-GAME-NOT-FOUND)
    (asserts! (is-game-owner game-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? game-collections { 
      game-id: game-id, 
      collection-contract: collection-contract 
    })) ERR-COLLECTION-EXISTS)
    
    (map-set game-collections
      { 
        game-id: game-id, 
        collection-contract: collection-contract 
      }
      {
        name: name,
        description: description,
        attributes: attributes,
        active: true
      }
    )
    (ok true)
  )
)

;; Update a collection for a game
(define-public (update-collection
  (game-id (string-ascii 64))
  (collection-contract principal)
  (name (string-utf8 100))
  (description (string-utf8 500))
  (attributes (list 20 (string-ascii 64)))
  (active bool)
)
  (begin
    (asserts! (game-exists game-id) ERR-GAME-NOT-FOUND)
    (asserts! (is-game-owner game-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? game-collections { 
      game-id: game-id, 
      collection-contract: collection-contract 
    })) ERR-COLLECTION-NOT-FOUND)
    
    (map-set game-collections
      { 
        game-id: game-id, 
        collection-contract: collection-contract 
      }
      {
        name: name,
        description: description,
        attributes: attributes,
        active: active
      }
    )
    (ok true)
  )
)

;; Create a mapping between assets in different games
(define-public (create-asset-mapping
  (source-game-id (string-ascii 64))
  (source-collection principal)
  (target-game-id (string-ascii 64))
  (target-collection principal)
  (attribute-mappings (list 20 {
    source-attribute: (string-ascii 64),
    target-attribute: (string-ascii 64),
    transformation: (optional (string-ascii 64))
  }))
)
  (begin
    ;; Check that both games exist
    (asserts! (game-exists source-game-id) ERR-GAME-NOT-FOUND)
    (asserts! (game-exists target-game-id) ERR-GAME-NOT-FOUND)
    
    ;; Ensure caller is authorized (owner of source game)
    (asserts! (is-game-owner source-game-id) ERR-NOT-AUTHORIZED)
    
    ;; Verify collections exist in their respective games
    (asserts! (is-some (map-get? game-collections { 
      game-id: source-game-id, 
      collection-contract: source-collection 
    })) ERR-COLLECTION-NOT-FOUND)
    
    (asserts! (is-some (map-get? game-collections { 
      game-id: target-game-id, 
      collection-contract: target-collection 
    })) ERR-COLLECTION-NOT-FOUND)
    
    ;; Ensure mapping doesn't already exist
    (asserts! (is-none (map-get? asset-mappings {
      source-game-id: source-game-id,
      source-collection: source-collection,
      target-game-id: target-game-id
    })) ERR-MAPPING-EXISTS)
    
    ;; Create the mapping
    (map-set asset-mappings
      {
        source-game-id: source-game-id,
        source-collection: source-collection,
        target-game-id: target-game-id
      }
      {
        target-collection: target-collection,
        attribute-mappings: attribute-mappings,
        active: true
      }
    )
    (ok true)
  )
)

;; Update an existing asset mapping
(define-public (update-asset-mapping
  (source-game-id (string-ascii 64))
  (source-collection principal)
  (target-game-id (string-ascii 64))
  (target-collection principal)
  (attribute-mappings (list 20 {
    source-attribute: (string-ascii 64),
    target-attribute: (string-ascii 64),
    transformation: (optional (string-ascii 64))
  }))
  (active bool)
)
  (begin
    ;; Check that both games exist
    (asserts! (game-exists source-game-id) ERR-GAME-NOT-FOUND)
    (asserts! (game-exists target-game-id) ERR-GAME-NOT-FOUND)
    
    ;; Ensure caller is authorized (owner of source game)
    (asserts! (is-game-owner source-game-id) ERR-NOT-AUTHORIZED)
    
    ;; Verify mapping exists
    (asserts! (is-some (map-get? asset-mappings {
      source-game-id: source-game-id,
      source-collection: source-collection,
      target-game-id: target-game-id
    })) ERR-MAPPING-NOT-FOUND)
    
    ;; Update the mapping
    (map-set asset-mappings
      {
        source-game-id: source-game-id,
        source-collection: source-collection,
        target-game-id: target-game-id
      }
      {
        target-collection: target-collection,
        attribute-mappings: attribute-mappings,
        active: active
      }
    )
    (ok true)
  )
)

;; Delete an asset mapping
(define-public (delete-asset-mapping
  (source-game-id (string-ascii 64))
  (source-collection principal)
  (target-game-id (string-ascii 64))
)
  (begin
    ;; Ensure caller is authorized (owner of source game)
    (asserts! (is-game-owner source-game-id) ERR-NOT-AUTHORIZED)

    ;; Verify mapping exists (unwrap-panic relies on this)
    (asserts! (is-some (map-get? asset-mappings {
      source-game-id: source-game-id,
      source-collection: source-collection,
      target-game-id: target-game-id
    })) ERR-MAPPING-NOT-FOUND)

    ;; Get the mapping data (safe due to assert!)
    (let ((mapping-data (unwrap-panic (map-get? asset-mappings {
      source-game-id: source-game-id,
      source-collection: source-collection,
      target-game-id: target-game-id
    }))))
      ;; Update the mapping to inactive
      (map-set asset-mappings
        {
          source-game-id: source-game-id,
          source-collection: source-collection,
          target-game-id: target-game-id
        }
        (merge mapping-data { active: false })
      )
    ) ;; end let

    ;; Return success
    (ok true)
  )
)