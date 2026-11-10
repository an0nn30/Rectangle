/// StringExtension.swift

import Foundation

extension String {
    
    var localized: String {
        NSLocalizedString(self, tableName: "Main", comment: "")
    }
    
}
