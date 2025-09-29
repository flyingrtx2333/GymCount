//
//  SettingsView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.presentationMode) var presentationMode
    @State private var tempSettings: AppSettings
    
    init() {
        _tempSettings = State(initialValue: DataManager.shared.settings)
    }
    
    var body: some View {
        NavigationView {
            List {
                // 默认重量设置
                Section(header: Text(NSLocalizedString("weight", comment: "重量"))) {
                    HStack {
                        Text("默认重量")
                        Spacer()
                        Text("\(Int(tempSettings.defaultWeight)) \(NSLocalizedString("kg", comment: "公斤"))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button(action: {
                            if tempSettings.defaultWeight > 0 {
                                tempSettings.defaultWeight -= 2.5
                            }
                        }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Button(action: {
                            tempSettings.defaultWeight += 2.5
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // 应用信息
                Section(header: Text("应用信息")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("开发者")
                        Spacer()
                        Text("向钧升")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "取消")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "保存")) {
                        dataManager.updateSettings(tempSettings)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataManager.shared)
}
