import FungibleToken from 0xf233dcee88fe0abe
import NonFungibleToken from 0x1d7e57aa55817448
import NFTStorefront from 0x4eb8a10cb9f87357
import Marketplace from 0xdc5127882cacf8d9
import FlowToken from 0x1654653399040a61
import Vouchers from 0x444f5ea22c6ea12c

transaction(saleItemID: UInt64, saleItemPrice: UFix64) {
    let flowTokenReceiver: Capability<&FlowToken.Vault{FungibleToken.Receiver}>
    let nftProvider: Capability<&Vouchers.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>
    let storefront: &NFTStorefront.Storefront
    let storefrontPublic: Capability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>

    prepare(signer: AuthAccount) {
        // Create Storefront if it doesn't exist
        if signer.borrow<&NFTStorefront.Storefront>(from: NFTStorefront.StorefrontStoragePath) == nil {
            let storefront <- NFTStorefront.createStorefront() as! @NFTStorefront.Storefront
            signer.save(<-storefront, to: NFTStorefront.StorefrontStoragePath)
            signer.link<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(
                NFTStorefront.StorefrontPublicPath,
                target: NFTStorefront.StorefrontStoragePath)
        }

        // We need a provider capability, but one is not provided by default so we create one if needed.
        let nftCollectionProviderPrivatePath = /private/jambbVouchersNFTCollectionProviderForNFTStorefront
        if !signer.getCapability<&Vouchers.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(nftCollectionProviderPrivatePath)!.check() {
            signer.link<&Vouchers.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(nftCollectionProviderPrivatePath, target: Vouchers.CollectionStoragePath)
        }

        self.flowTokenReceiver = signer.getCapability<&FlowToken.Vault{FungibleToken.Receiver}>(/public/flowTokenReceiver)!
        assert(self.flowTokenReceiver.borrow() != nil, message: "Missing or mis-typed FlowToken receiver")

        self.nftProvider = signer.getCapability<&Vouchers.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(nftCollectionProviderPrivatePath)!
        assert(self.nftProvider.borrow() != nil, message: "Missing or mis-typed Vouchers.Collection provider")

        self.storefront = signer.borrow<&NFTStorefront.Storefront>(from: NFTStorefront.StorefrontStoragePath)
            ?? panic("Missing or mis-typed NFTStorefront Storefront")

        self.storefrontPublic = signer.getCapability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(NFTStorefront.StorefrontPublicPath)
        assert(self.storefrontPublic.borrow() != nil, message: "Could not borrow public storefront from address")
    }

    execute {
        // Remove old listing
        if let listingID = Marketplace.getListingID(nftType: Type<@Vouchers.NFT>(), nftID: saleItemID) {
            let listingIDs = self.storefront.getListingIDs()
            if listingIDs.contains(listingID) {
                self.storefront.removeListing(listingResourceID: listingID)
            }
            Marketplace.removeListing(id: listingID)
        }

        // Create SaleCuts
        var saleCuts: [NFTStorefront.SaleCut] = []
        let requirements = Marketplace.getSaleCutRequirements(nftType: Type<@Vouchers.NFT>())
        var remainingPrice = saleItemPrice
        for requirement in requirements {
            let price = saleItemPrice * requirement.ratio
            saleCuts.append(NFTStorefront.SaleCut(
                receiver: requirement.receiver,
                amount: price
            ))
            remainingPrice = remainingPrice - price
        }
        saleCuts.append(NFTStorefront.SaleCut(
            receiver: self.flowTokenReceiver,
            amount: remainingPrice
        ))

        // Add listing
        let id = self.storefront.createListing(
            nftProviderCapability: self.nftProvider,
            nftType: Type<@Vouchers.NFT>(),
            nftID: saleItemID,
            salePaymentVaultType: Type<@FlowToken.Vault>(),
            saleCuts: saleCuts
        )
        Marketplace.addListing(id: id, storefrontPublicCapability: self.storefrontPublic)
    }
}