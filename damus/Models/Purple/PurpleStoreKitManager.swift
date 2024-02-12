//
//  PurpleStoreKitManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import Foundation
import StoreKit

extension DamusPurple {
    class StoreKitManager { // Has to be a class to get around Swift-imposed limitations of mutations on concurrently executing code
        var delegate: DamusPurpleStoreKitManagerDelegate? = nil {
            didSet {
                // Whenever the delegate is set, send it all recorded transactions.
                Task {
                    Log.info("Delegate changed. Try sending all recorded valid product transactions", for: .damus_purple)
                    guard let new_delegate = delegate else {
                        Log.info("Delegate is nil. Cannot send recorded product transactions", for: .damus_purple)
                        return
                    }
                    Log.info("Sending all %d recorded valid product transactions", for: .damus_purple, self.recorded_purchased_products.count)
                    
                    for purchased_product in self.recorded_purchased_products {
                        new_delegate.product_was_purchased(product: purchased_product)
                        Log.info("Sent tx to delegate", for: .damus_purple)
                    }
                }
            }
        }
        var recorded_purchased_products: [PurchasedProduct] = []
        
        struct PurchasedProduct {
            let tx: StoreKit.Transaction
            let product: Product
        }
        
        static let standard = StoreKitManager()
        
        init() {
            Log.info("Initiliazing StoreKitManager", for: .damus_purple)
            self.start()
        }
        
        func start() {
            Task {
                try await monitor_updates()
            }
        }
        
        func get_products() async throws -> [Product] {
            return try await Product.products(for: DamusPurpleType.allCases.map({ $0.rawValue }))
        }
        
        func record_purchased_product(_ purchased_product: PurchasedProduct) {
            self.recorded_purchased_products.append(purchased_product)
            self.delegate?.product_was_purchased(product: purchased_product)
        }
        
        private func monitor_updates() async throws {
            Log.info("Monitoring StoreKit updates", for: .damus_purple)
            for await update in StoreKit.Transaction.updates {
                switch update {
                    case .verified(let tx):
                        let products = try await self.get_products()
                        let prod = products.filter({ prod in tx.productID == prod.id }).first
                        
                        if let prod,
                           let expiration = tx.expirationDate,
                           Date.now < expiration
                        {
                            Log.info("Received valid transaction update from StoreKit", for: .damus_purple)
                            let purchased_product = PurchasedProduct(tx: tx, product: prod)
                            self.recorded_purchased_products.append(purchased_product)
                            self.delegate?.product_was_purchased(product: purchased_product)
                            Log.info("Sent tx to delegate (if exists)", for: .damus_purple)
                        }
                    case .unverified:
                        continue
                }
            }
        }
        
        func purchase(product: Product, id: UUID) async throws -> Product.PurchaseResult {
            return try await product.purchase(options: [.appAccountToken(id)])
        }
    }
}

extension DamusPurple.StoreKitManager {
    enum DamusPurpleType: String, CaseIterable {
        case yearly = "purpleyearly"
        case monthly = "purple"
        
        func non_discounted_price(product: Product) -> String? {
            switch self {
                case .yearly:
                    return (product.price * 1.1984569224).formatted(product.priceFormatStyle)
                case .monthly:
                    return nil
            }
        }
        
        func label() -> String {
            switch self {
                case .yearly:
                    return NSLocalizedString("Annually", comment: "Annual renewal of purple subscription")
                case .monthly:
                    return NSLocalizedString("Monthly", comment: "Monthly renewal of purple subscription")
            }
        }
    }
}

protocol DamusPurpleStoreKitManagerDelegate {
    func product_was_purchased(product: DamusPurple.StoreKitManager.PurchasedProduct)
}
